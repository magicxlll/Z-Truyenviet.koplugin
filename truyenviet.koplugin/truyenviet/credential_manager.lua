local Storage = require("truyenviet/storage")
local Debug = require("truyenviet/debugger")

local CredentialManager = {}

local ENCRYPTION_KEY = "TruyenViet_KOReader_2024_SecureKey"

local function ensureAesLoaded()
    if CredentialManager._aes_loaded then
        return true
    end
    local ok = pcall(function()
        local current_dir = "truyenviet/sources/"
        if not string.find(package.path, "aeslua[/\\]src[/\\]%?%.lua", 1, true) then
            package.path = package.path .. ";" .. current_dir .. "aeslua/src/?.lua;" .. current_dir .. "?.lua"
        end
        require("aeslua")
    end)
    if ok then
        CredentialManager._aes_loaded = true
    end
    return ok
end

local function bytesToHex(str)
    local hex = {}
    for i = 1, #str do
        hex[i] = string.format("%02x", str:byte(i))
    end
    return table.concat(hex)
end

local function hexToBytes(hex)
    local bytes = {}
    for i = 1, #hex, 2 do
        bytes[#bytes + 1] = string.char(tonumber(hex:sub(i, i + 1), 16))
    end
    return table.concat(bytes)
end

function CredentialManager:encrypt(plaintext)
    if not ensureAesLoaded() then
        Debug.write("[CredentialManager] AES library not available, storing base64")
        -- Fallback: simple base64-like obfuscation (not true encryption)
        local result = {}
        for i = 1, #plaintext do
            result[i] = string.format("%02x", bit32 and bit32.bxor(plaintext:byte(i), 0x5A) or (plaintext:byte(i) + 42) % 256)
        end
        return "obf:" .. table.concat(result)
    end
    local cipher = aeslua.encrypt(ENCRYPTION_KEY, plaintext)
    if cipher then
        return "aes:" .. bytesToHex(cipher)
    end
    return nil, "Mã hóa thất bại"
end

function CredentialManager:decrypt(encrypted)
    if not encrypted or encrypted == "" then
        return nil
    end
    if encrypted:sub(1, 4) == "obf:" then
        local hex = encrypted:sub(5)
        local result = {}
        for i = 1, #hex, 2 do
            local byte = tonumber(hex:sub(i, i + 1), 16)
            result[#result + 1] = string.char(bit32 and bit32.bxor(byte, 0x5A) or (byte - 42) % 256)
        end
        return table.concat(result)
    end
    if encrypted:sub(1, 4) == "aes:" then
        if not ensureAesLoaded() then
            return nil, "Thư viện AES không khả dụng"
        end
        local cipher = hexToBytes(encrypted:sub(5))
        local plain = aeslua.decrypt(ENCRYPTION_KEY, cipher)
        return plain
    end
    -- Legacy plaintext
    return encrypted
end

function CredentialManager:saveCredential(source_id, username, password)
    Storage:initialize()
    local encrypted, err = self:encrypt(password)
    if not encrypted then
        return nil, err or "Không thể mã hóa mật khẩu"
    end
    local credentials = Storage.settings:readSetting("credentials", {})
    if type(credentials) ~= "table" then
        credentials = {}
    end
    credentials[source_id] = {
        username = username,
        password = encrypted,
    }
    Storage.settings:saveSetting("credentials", credentials)
    Storage.settings:flush()
    Debug.write("[CredentialManager] Saved credential for " .. source_id)
    return true
end

function CredentialManager:getCredential(source_id)
    Storage:initialize()
    local credentials = Storage.settings:readSetting("credentials", {})
    if type(credentials) ~= "table" then
        return nil
    end
    local cred = credentials[source_id]
    if not cred or type(cred) ~= "table" then
        return nil
    end
    local password = self:decrypt(cred.password)
    if not password then
        return nil, "Không thể giải mã mật khẩu"
    end
    return {
        username = cred.username,
        password = password,
    }
end

function CredentialManager:hasCredential(source_id)
    Storage:initialize()
    local credentials = Storage.settings:readSetting("credentials", {})
    if type(credentials) ~= "table" then
        return false
    end
    local cred = credentials[source_id]
    return cred ~= nil and type(cred) == "table" and cred.username ~= nil
end

function CredentialManager:removeCredential(source_id)
    Storage:initialize()
    local credentials = Storage.settings:readSetting("credentials", {})
    if type(credentials) ~= "table" then
        return true
    end
    credentials[source_id] = nil
    Storage.settings:saveSetting("credentials", credentials)
    Storage.settings:flush()
    Debug.write("[CredentialManager] Removed credential for " .. source_id)
    return true
end

local DEFAULT_FIRECRAWL_KEY = "fc-8d74d9b08d5a4677b6c715834d4e8cec"

function CredentialManager:saveFirecrawlKey(key)
    Storage:initialize()
    if not key or key == "" then
        return Storage.settings:saveSetting("firecrawl_api_key", nil)
    end
    local encrypted, err = self:encrypt(key)
    if not encrypted then
        return nil, err or "Không thể mã hóa API Key"
    end
    Storage.settings:saveSetting("firecrawl_api_key", encrypted)
    Storage.settings:flush()
    return true
end

function CredentialManager:getFirecrawlKey()
    Storage:initialize()
    local encrypted = Storage.settings:readSetting("firecrawl_api_key")
    if not encrypted or type(encrypted) ~= "string" or encrypted == "" then
        return DEFAULT_FIRECRAWL_KEY
    end
    local key = self:decrypt(encrypted)
    return (key and key ~= "") and key or DEFAULT_FIRECRAWL_KEY
end

function CredentialManager:getMaskedFirecrawlKey()
    local key = self:getFirecrawlKey()
    if not key or key == "" then
        return "Chưa cài đặt"
    end
    if key == DEFAULT_FIRECRAWL_KEY then
        return "Hệ thống tích hợp (" .. key:sub(1, 7) .. "..." .. key:sub(-4) .. ")"
    end
    if #key > 10 then
        return key:sub(1, 7) .. "..." .. key:sub(-4)
    end
    return "******"
end

return CredentialManager

