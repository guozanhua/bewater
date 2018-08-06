local skynet    = require "skynet"
local socket    = require "skynet.socket"
local ws_server = require "ws.server"
local class     = require "class"
local util      = require "util"
local opcode    = require "def.opcode"
local errcode   = require "def.errcode"
local protobuf  = require "protobuf"
local json      = require "cjson"

local M = class("network_t")
function M:ctor(player)
    self.player = assert(player, "network need player")
end

function M:init(agent, fd)
    self._agent = agent
    self._fd = fd

    local handler = {}
    function handler.open()
    end
    function handler.text(t)
        self.send_type = "text"
        self:_recv_text(t)
    end
    function handler.binary(sock_buff)
        self.send_type = "binary"
        self:_recv_binary(sock_buff)
    end
    function handler.close()
    end
    self._ws = ws_server.new(fd, handler)
end

function M:send(...)
    if self.send_type == "binary" then
        self:_send_binary(...)
    elseif self.send_type == "text" then
        self:_send_text(...)
    else
        error(string.format("send error send_type:%s", self.send_type))
    end
end

function M:_send_text(id, msg) -- 兼容text
    self._ws:send_text(json.encode({
        id  = id,
        msg = msg,
    }))
end

function M:_send_binary(op, tbl)
    local data = protobuf.encode(opcode.toname(op), tbl)
    print("send", #data)
    self._ws:send_binary(string.pack(">Hs2", op, data))
end

function M:_recv_text(t)
    local data = json.decode(t)
    local recv_id = data.id
    if recv_id == "HearBeatPing" then
        -- todo change name
        return message
    end
    local resp_id = "S2c"..string.match(recv_id, "C2s(.+)")
    assert(self.player[recv_id], "net handler nil")
    if self.player[recv_id] then
        local msg = self.player[recv_id](self.player, data.msg) or {}
        self._ws:send_text(json.encode({
            id = resp_id,
            msg = msg,
        }))
    end
end

function M:_recv_binary(sock_buff)
    local op, buff = string.unpack(">Hs2", sock_buff)
    local opname = opcode.toname(op)
    local modulename = opcode.tomodule(op)
    local simplename = opcode.tosimplename(op)
    if opcode.has_session(op) then
        print(string.format("recv package, 0x%x %s", op, opname))
    end

    local data = protobuf.decode(opname, buff, sz)
    util.printdump(data)

    if not util.try(function()
        assert(player, "player nil")
        assert(player[modulename], string.format("module nil [%s.%s]", modulename, simplename))
        assert(player[modulename][simplename], string.format("handle nil [%s.%s]", modulename, simplename))
        ret = player[modulename][simplename](player[modulename], data) or 0
    end) then
        ret = errcode.Traceback
    end 

    assert(ret, string.format("no respone, opname %s", opname))
    if type(ret) == "table" then
        ret.err = ret.err or 0
    else
        ret = {err = ret} 
    end                                                                                                                                                                                                                              
    self:send(op+1, ret)
end

return M
