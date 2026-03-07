const std = @import("std");
const c = @cImport(@cInclude("uvgrtp/wrapper_c.h"));

pub fn main() !void {
    const ctx = c.uvgrtp_create_ctx();
    if (ctx == null) {
        return error.InitialisationError;
    }
}
