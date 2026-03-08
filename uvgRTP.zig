const std = @import("std");

// Just in case I forgot to wrap something.
pub const c = @cImport(@cInclude("uvgrtp/wrapper_c.h"));

pub fn getUvgRTPErrorNo() c_int {
    return c.rtp_errno;
}

pub const UvgRTPError = error{
    InitialisationError,
    OperationFailed,
};

fn ensureOk(result: c_int) UvgRTPError!void {
    if (result != c.RTP_OK) {
        return error.OperationFailed;
    }
}

pub const RtpFormat = enum(c_int) {
    generic_or_pcmu = c.RTP_FORMAT_GENERIC,
    gsm = c.RTP_FORMAT_GSM,
    g723 = c.RTP_FORMAT_G723,
    dvi4_32 = c.RTP_FORMAT_DVI4_32,
    dvi4_64 = c.RTP_FORMAT_DVI4_64,
    lpc = c.RTP_FORMAT_LPC,
    pcma = c.RTP_FORMAT_PCMA,
    g722 = c.RTP_FORMAT_G722,
    l16_stereo = c.RTP_FORMAT_L16_STEREO,
    l16_mono = c.RTP_FORMAT_L16_MONO,
    g728 = c.RTP_FORMAT_G728,
    dvi4_441 = c.RTP_FORMAT_DVI4_441,
    dvi4_882 = c.RTP_FORMAT_DVI4_882,
    g729 = c.RTP_FORMAT_G729,
    g726_40 = c.RTP_FORMAT_G726_40,
    g726_32 = c.RTP_FORMAT_G726_32,
    g726_24 = c.RTP_FORMAT_G726_24,
    g726_16 = c.RTP_FORMAT_G726_16,
    g729d = c.RTP_FORMAT_G729D,
    g729e = c.RTP_FORMAT_G729E,
    gsm_efr = c.RTP_FORMAT_GSM_EFR,
    l8 = c.RTP_FORMAT_L8,
    vdvi = c.RTP_FORMAT_VDVI,
    opus = c.RTP_FORMAT_OPUS,
    h264 = c.RTP_FORMAT_H264,
    h265 = c.RTP_FORMAT_H265,
    h266 = c.RTP_FORMAT_H266,
    atlas = c.RTP_FORMAT_ATLAS,
};

pub const RtpFlags = packed struct(u32) {
    obsolete: bool = false,
    copy: bool = false,
    no_h26x_scl: bool = false,
    h26x_do_not_aggr: bool = false,
    _reserved: u28 = 0,

    pub fn toInt(self: @This()) c_int {
        return @as(c_int, @intCast(@as(u32, @bitCast(self))));
    }
};

pub const RceFlags = packed struct(u32) {
    obsolete: bool = false,
    send_only: bool = false,
    receive_only: bool = false,
    srtp: bool = false,
    srtp_kmngmnt_zrtp: bool = false,
    srtp_kmngmnt_user: bool = false,
    no_h26x_prepend_sc: bool = false,
    h26x_dependency_enforcement: bool = false,
    fragment_generic: bool = false,
    system_call_clustering: bool = false,
    srtp_null_cipher: bool = false,
    srtp_authenticate_rtp: bool = false,
    srtp_replay_protection: bool = false,
    rtcp: bool = false,
    _reserved: u18 = 0,

    pub fn toInt(self: @This()) c_int {
        return @as(c_int, @intCast(@as(u32, @bitCast(self))));
    }
};

pub const FrameBuffer = struct {
    allocator: std.mem.Allocator,
    payload: []u8,

    pub fn init(allocator: std.mem.Allocator, payload_len: usize) !FrameBuffer {
        return FrameBuffer{
            .allocator = allocator,
            .payload = try allocator.alloc(u8, payload_len),
        };
    }

    pub fn initCopy(allocator: std.mem.Allocator, payload: []const u8) !FrameBuffer {
        const owned_payload = try allocator.alloc(u8, payload.len);
        @memcpy(owned_payload, payload);

        return FrameBuffer{
            .allocator = allocator,
            .payload = owned_payload,
        };
    }

    pub fn deinit(self: *FrameBuffer) void {
        self.allocator.free(self.payload);
        self.payload = &.{};
    }
};

pub const Frame = struct {
    handle: ?*c.uvgrtp_frame,

    fn fromHandle(handle: ?*c.uvgrtp_frame) UvgRTPError!Frame {
        if (handle == null) {
            return error.OperationFailed;
        }

        return Frame{ .handle = handle };
    }

    pub fn deinit(self: *Frame) void {
        if (self.handle) |frame| {
            c.uvgrtp_frame_free(frame);
        }
        self.handle = null;
    }

    pub fn payload(self: *const Frame) []u8 {
        const frame = self.handle orelse return &.{};
        return frame.payload[0..frame.payload_len];
    }

    pub fn payloadLen(self: *const Frame) usize {
        const frame = self.handle orelse return 0;
        return frame.payload_len;
    }

    pub fn ssrc(self: *const Frame) u32 {
        const frame = self.handle orelse return 0;
        return frame.ssrc;
    }

    pub fn timestamp(self: *const Frame) u32 {
        const frame = self.handle orelse return 0;
        return frame.timestamp;
    }

    pub fn sequence(self: *const Frame) u16 {
        const frame = self.handle orelse return 0;
        return frame.seq;
    }

    pub fn marker(self: *const Frame) u8 {
        const frame = self.handle orelse return 0;
        return frame.marker;
    }

    pub fn payloadType(self: *const Frame) u8 {
        const frame = self.handle orelse return 0;
        return frame.payload_type;
    }
};

pub const Context = struct {
    handle: ?*c.struct_uvgrtp_context_handle,

    pub fn init() !Context {
        const ctx = c.uvgrtp_create_ctx();

        if (ctx == null) {
            return error.InitialisationError;
        }

        return Context{ .handle = ctx };
    }

    pub fn deinit(self: Context) void {
        c.uvgrtp_destroy_ctx(self.handle);
    }
};

pub const Session = struct {
    handle: ?*c.struct_uvgrtp_session_handle,

    pub fn init(ctx: *Context, remote_address: [:0]const u8) !Session {
        return initAddrPair(ctx, remote_address, null);
    }

    pub fn initAddrPair(
        ctx: *Context,
        remote_address: [:0]const u8,
        local_address: ?[:0]const u8,
    ) !Session {
        var session: ?*c.struct_uvgrtp_session_handle = undefined;

        if (local_address) |local_addr| {
            session = c.uvgrtp_create_session_addr_pair(ctx.handle, remote_address, local_addr);
        } else {
            session = c.uvgrtp_create_session(ctx.handle, remote_address);
        }

        if (session == null) {
            return error.InitialisationError;
        }

        return Session{ .handle = session };
    }

    pub fn deinit(self: *Session, ctx: *Context) UvgRTPError!void {
        if (self.handle) |session| {
            try ensureOk(c.uvgrtp_destroy_session(ctx.handle, session));
        }
        self.handle = null;
    }

    pub fn createStream(
        self: *Session,
        local_port: u16,
        remote_port: u16,
        rtp_format: RtpFormat,
        rce_flags: RceFlags,
    ) !Stream {
        return Stream.init(self, local_port, remote_port, rtp_format, rce_flags);
    }

    pub fn createStreamRaw(
        self: *Session,
        local_port: u16,
        remote_port: u16,
        rtp_format: c_int,
        rce_flags: c_int,
    ) !Stream {
        return Stream.initRaw(self, local_port, remote_port, rtp_format, rce_flags);
    }
};

pub const Stream = struct {
    handle: ?*c.struct_uvgrtp_stream_handle,

    pub fn init(
        session: *Session,
        local_port: u16,
        remote_port: u16,
        rtp_format: RtpFormat,
        rce_flags: RceFlags,
    ) !Stream {
        return initRaw(
            session,
            local_port,
            remote_port,
            @intFromEnum(rtp_format),
            rce_flags.toInt(),
        );
    }

    pub fn initRaw(
        session: *Session,
        local_port: u16,
        remote_port: u16,
        rtp_format: c_int,
        rce_flags: c_int,
    ) !Stream {
        const stream = c.uvgrtp_create_stream(
            session.handle,
            local_port,
            remote_port,
            rtp_format,
            rce_flags,
        );

        if (stream == null) {
            return error.InitialisationError;
        }

        return Stream{ .handle = stream };
    }

    pub fn deinit(self: *Stream, session: *Session) UvgRTPError!void {
        if (self.handle) |stream| {
            try ensureOk(c.uvgrtp_destroy_stream(session.handle, stream));
        }
        self.handle = null;
    }

    pub fn pushFrame(self: *Stream, payload: []u8, rtp_flags: RtpFlags) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame(self.handle, payload.ptr, payload.len, rtp_flags.toInt()));
    }

    pub fn pushFrameRaw(self: *Stream, payload: []u8, rtp_flags: c_int) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame(self.handle, payload.ptr, payload.len, rtp_flags));
    }

    pub fn pushFrameConst(self: *Stream, payload: []const u8, rtp_flags: RtpFlags) UvgRTPError!void {
        try self.pushFrame(@constCast(payload), rtp_flags);
    }

    pub fn pushFrameBuffer(self: *Stream, frame: *const FrameBuffer, rtp_flags: RtpFlags) UvgRTPError!void {
        try self.pushFrame(frame.payload, rtp_flags);
    }

    pub fn pushFrameTs(self: *Stream, payload: []u8, rtp_ts: u32, rtp_flags: RtpFlags) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame_ts(self.handle, payload.ptr, payload.len, rtp_ts, rtp_flags.toInt()));
    }

    pub fn pushFrameTsRaw(self: *Stream, payload: []u8, rtp_ts: u32, rtp_flags: c_int) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame_ts(self.handle, payload.ptr, payload.len, rtp_ts, rtp_flags));
    }

    pub fn pushFrameNtp(
        self: *Stream,
        payload: []u8,
        rtp_ts: u32,
        ntp_ts: u64,
        rtp_flags: RtpFlags,
    ) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame_ntp(self.handle, payload.ptr, payload.len, rtp_ts, ntp_ts, rtp_flags.toInt()));
    }

    pub fn pushFrameNtpRaw(
        self: *Stream,
        payload: []u8,
        rtp_ts: u32,
        ntp_ts: u64,
        rtp_flags: c_int,
    ) UvgRTPError!void {
        try ensureOk(c.uvgrtp_push_frame_ntp(self.handle, payload.ptr, payload.len, rtp_ts, ntp_ts, rtp_flags));
    }

    pub fn pullFrame(self: *Stream) UvgRTPError!Frame {
        return Frame.fromHandle(c.uvgrtp_pull_frame(self.handle));
    }

    pub fn pullFrameTimeout(self: *Stream, timeout_ms: usize) UvgRTPError!?Frame {
        const frame = c.uvgrtp_pull_frame_timeout(self.handle, timeout_ms);
        if (frame == null) {
            if (c.rtp_errno == c.RTP_TIMEOUT) {
                return null;
            }
            return error.OperationFailed;
        }

        return Frame{ .handle = frame };
    }

    pub fn configure(self: *Stream, rcc_flag: c_int, value: c_int) UvgRTPError!void {
        try ensureOk(c.uvgrtp_configure(self.handle, rcc_flag, value));
    }

    pub fn getConfiguration(self: *Stream, rcc_flag: c_int) UvgRTPError!c_int {
        const value = c.uvgrtp_get_configuration(self.handle, rcc_flag);
        if (value < 0) {
            return error.OperationFailed;
        }
        return value;
    }

    pub fn getSsrc(self: *Stream) u32 {
        return c.uvgrtp_get_ssrc(self.handle);
    }

    pub fn addSrtpCtx(self: *Stream, key: []u8, salt: []u8) UvgRTPError!void {
        try ensureOk(c.uvgrtp_add_srtp_ctx(self.handle, key.ptr, salt.ptr));
    }

    pub fn startZrtp(self: *Stream) UvgRTPError!void {
        try ensureOk(c.uvgrtp_start_zrtp(self.handle));
    }
};
