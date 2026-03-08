const std = @import("std");

const rtp = @import("uvgRTP");

const REMOTE_PORT = 8891;
const LOCAL_PORT = 8890;
const REMOTE_ADDRESS = "127.0.0.1";
const N_TEST_PACKETS = 100;

pub fn main() !void {
    var ctx = try rtp.Context.init();
    defer ctx.deinit();

    var session = try rtp.Session.init(&ctx, REMOTE_ADDRESS);
    defer session.deinit(&ctx) catch |e| {
        std.log.err(
            "Could not deinitialise Session with error: {any}, errno: {d}.",
            .{ e, rtp.getUvgRTPErrorNo() },
        );
    };

    const flags = rtp.RceFlags{ .receive_only = true };

    var opus_stream = try rtp.Stream.init(
        &session,
        LOCAL_PORT,
        REMOTE_PORT,
        .opus,
        flags,
    );
    defer opus_stream.deinit(&session) catch |e| {
        std.log.err(
            "Could not deinitialise Opus RTP Stream with error: {any}, errno: {d}.",
            .{ e, rtp.getUvgRTPErrorNo() },
        );
    };

    var recieved: u8 = 0;
    while (recieved < N_TEST_PACKETS) : (recieved += 1) {
        var frame = try opus_stream.pullFrame();
        defer frame.deinit();

        std.log.info(
            "Recieved frame {d}/{d}, payload_len = {d}",
            .{ recieved, N_TEST_PACKETS, frame.payloadLen() },
        );
    }
}
