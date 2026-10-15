-- mod_http_upload_s3
--
-- Implements the XEP-0363 HTTP File Upload slot request, but instead of
-- serving uploads via Prosody's HTTP server it generates AWS S3 (or
-- S3-compatible, e.g. MinIO) presigned URLs. Clients upload directly to
-- object storage and receive a GET URL to share.
--
-- When s3_public_url is set, GET links point at that base URL (e.g. a CDN
-- or public bucket website endpoint) and never expire. Otherwise GET links
-- are presigned and expire after s3_get_expiry seconds (max 7 days).
--
-- Object lifecycle (expiry/deletion of old files) is not handled by this
-- module. Configure a bucket lifecycle rule to expire objects.
--
-- Component options:
--   s3_bucket          (required) bucket name
--   s3_access_key      (required)
--   s3_secret_key      (required)
--   s3_region          default "us-east-1"
--   s3_endpoint        default "https://s3.{region}.amazonaws.com"
--   s3_path_style      default false (virtual-hosted style); set true for MinIO
--   s3_public_url      optional base URL for GET links
--   s3_key_prefix      optional prefix added to all object keys
--   s3_put_expiry      PUT URL validity in seconds, default 3600 (max 604800)
--   s3_get_expiry      GET URL validity in seconds, default 604800 (max 604800)
--   s3_file_size_limit per-file size limit in bytes, default 10MB
--   s3_allowed_file_types  optional set of MIME types (wildcards like image/* allowed)

module:depends("disco");

local st = require "prosody.util.stanza";
local jid = require "prosody.util.jid";
local errors = require "prosody.util.error";
local dataform = require "prosody.util.dataforms".new;
local hashes = require "prosody.util.hashes";
local httputil = require "prosody.util.http";
local uuid = require "prosody.util.uuid";
local url = require "socket.url";
local hi = require "prosody.util.human.units";

local sha256 = hashes.sha256;
local hmac_sha256 = hashes.hmac_sha256;
local urlencode = httputil.urlencode;

local namespace = "urn:xmpp:http:upload:0";

local bucket = assert(module:get_option_string("s3_bucket"), "mod_http_upload_s3: s3_bucket is required");
local region = module:get_option_string("s3_region", "us-east-1");
local endpoint = module:get_option_string("s3_endpoint", ("https://s3.%s.amazonaws.com"):format(region));
local access_key = assert(module:get_option_string("s3_access_key"), "mod_http_upload_s3: s3_access_key is required");
local secret_key = assert(module:get_option_string("s3_secret_key"), "mod_http_upload_s3: s3_secret_key is required");
local path_style = module:get_option_boolean("s3_path_style", false);
local public_url = module:get_option_string("s3_public_url");
local key_prefix = module:get_option_string("s3_key_prefix", "");
local put_expiry = math.min(module:get_option_integer("s3_put_expiry", 3600, 0), 604800);
local get_expiry = math.min(module:get_option_integer("s3_get_expiry", 604800, 0), 604800);
local file_size_limit = module:get_option_integer("s3_file_size_limit", 10 * 1024 * 1024, 0);
local file_types = module:get_option_set("s3_allowed_file_types", {});
local access = module:get_option_set("s3_access", {});

module:default_permission("prosody:registered", ":upload");

module:add_identity("store", "file", module:get_option_string("name", "HTTP File Upload"));
module:add_feature(namespace);

module:add_extension(dataform {
	{ name = "FORM_TYPE", type = "hidden", value = namespace },
	{ name = "max-file-size", type = "text-single", datatype = "xs:integer" },
}:form({ ["max-file-size"] = file_size_limit }, "result"));

local upload_errors = errors.init(module.name, namespace, {
	access = { type = "auth"; condition = "forbidden" };
	filename = { type = "modify"; condition = "bad-request"; text = "Invalid filename" };
	filetype = { type = "modify"; condition = "not-acceptable"; text = "File type not allowed" };
	filesize = {
		code = 413;
		type = "modify";
		condition = "not-acceptable";
		text = "File too large"; -- also used if file is too small
		extra = {
			tag = st.stanza("file-too-large", { xmlns = namespace }):tag("max-file-size"):text(tostring(file_size_limit));
		};
	};
	filesizefmt = { type = "modify"; condition = "bad-request"; text = "File size missing or invalid" };
});

local endpoint_url = url.parse(endpoint);
local endpoint_scheme = endpoint_url.scheme or "https";
local endpoint_host = endpoint_url.host;
local endpoint_base_path = (endpoint_url.path or "/"):gsub("/+$", "");
assert(endpoint_host, "mod_http_upload_s3: could not parse s3_endpoint");

-- The Host header that must appear in signed requests (includes port when set)
local endpoint_hostport = endpoint_url.port
	and ("%s:%d"):format(endpoint_host, endpoint_url.port)
	or endpoint_host;

local function aws4_encode(s)
	return (urlencode(s):gsub("%%%x%x", string.upper));
end

local function encode_path(path)
	-- URI-encode each path segment, preserving '/' separators
	return (path:gsub("([^/]+)", aws4_encode));
end

local function canonical_uri(key)
	if path_style then
		return encode_path(endpoint_base_path.."/"..bucket.."/"..key);
	end
	return encode_path(endpoint_base_path.."/"..key);
end

local function request_hostport()
	if path_style then
		return endpoint_hostport;
	end
	return bucket.."."..endpoint_hostport;
end

local function presign(method, key, expiry)
	local amz_date = os.date("!%Y%m%dT%H%M%SZ");
	local short_date = amz_date:sub(1, 8);
	local scope = short_date.."/"..region.."/s3/aws4_request";

	local params = {
		{ name = "X-Amz-Algorithm"; value = "AWS4-HMAC-SHA256" };
		{ name = "X-Amz-Credential"; value = access_key.."/"..scope };
		{ name = "X-Amz-Date"; value = amz_date };
		{ name = "X-Amz-Expires"; value = tostring(expiry) };
		{ name = "X-Amz-SignedHeaders"; value = "host" };
	};
	table.sort(params, function(a, b) return a.name < b.name end);
	local canonical_query = httputil.formencode(params):gsub("%%%x%x", string.upper);

	local canonical_request = table.concat({
		method;
		canonical_uri(key);
		canonical_query;
		"host:"..request_hostport();
		"";
		"host";
		sha256("", true);
	}, "\n");

	local string_to_sign = "AWS4-HMAC-SHA256\n"..amz_date.."\n"..scope.."\n"..sha256(canonical_request, true);

	local k_date = hmac_sha256("AWS4"..secret_key, short_date);
	local k_region = hmac_sha256(k_date, region);
	local k_service = hmac_sha256(k_region, "s3");
	local k_signing = hmac_sha256(k_service, "aws4_request");
	local signature = hmac_sha256(k_signing, string_to_sign, true);

	return ("%s://%s%s?%s&X-Amz-Signature=%s"):format(
		endpoint_scheme, request_hostport(), canonical_uri(key), canonical_query, signature);
end

local function get_url(key)
	if public_url then
		return public_url:gsub("/+$", "")..encode_path("/"..key);
	end
	return presign("GET", key, get_expiry);
end

local function sanitize_filename(filename)
	-- Keep keys URL-safe so no additional encoding is needed anywhere
	local sanitized = filename:gsub("[^A-Za-z0-9%._%-]", "_"):gsub("^%.+", "");
	if #sanitized == 0 then
		sanitized = "file";
	end
	return sanitized:sub(1, 128);
end

local function may_upload(uploader, filename, filesize, filetype) --> boolean, error
	local uploader_host = jid.host(uploader);
	if not (module:may(":upload", uploader) or access:contains(uploader) or access:contains(uploader_host)) then
		return false, upload_errors.new("access");
	end

	if not filename or filename:find("/") then
		return false, upload_errors.new("filename");
	end

	if not filesize or filesize < 0 or filesize % 1 ~= 0 then
		return false, upload_errors.new("filesizefmt");
	end
	if filesize > file_size_limit then
		return false, upload_errors.new("filesize");
	end

	if not (file_types:empty() or file_types:contains(filetype) or file_types:contains(filetype:gsub("/.*", "/*"))) then
		return false, upload_errors.new("filetype");
	end

	return true;
end

function handle_slot_request(event)
	local stanza, origin = event.stanza, event.origin;

	local request = stanza.tags[1];
	local filename = request.attr.filename;
	local filesize = tonumber(request.attr.size);
	local filetype = request.attr["content-type"] or "application/octet-stream";
	local uploader = jid.bare(stanza.attr.from);

	local may, why_not = may_upload(uploader, filename, filesize, filetype);
	if not may then
		origin.send(st.error_reply(stanza, why_not));
		return true;
	end

	local new_uuid = uuid.v7 or uuid.generate;
	local key = key_prefix..module.host.."/"..os.date("!%Y-%m-%d").."/"..new_uuid().."/"..sanitize_filename(filename);

	module:log("info", "Issuing S3 upload slot to %s for %s (%s)", uploader, hi.format(filesize, "B", "b"), filetype);

	local reply = st.reply(stanza)
		:tag("slot", { xmlns = namespace })
			:tag("get", { url = get_url(key) }):up()
			:tag("put", { url = presign("PUT", key, put_expiry) })
		:reset();

	origin.send(reply);
	return true;
end

module:hook("iq-get/host/urn:xmpp:http:upload:0:request", handle_slot_request);
