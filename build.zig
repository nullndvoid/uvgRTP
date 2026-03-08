const std = @import("std");

const version_major = 3;
const version_minor = 1;
const version_patch = 6;
const version_string = std.fmt.comptimePrint("{d}.{d}.{d}", .{ version_major, version_minor, version_patch });

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const disable_crypto = b.option(bool, "disable_crypto", "Do not build uvgRTP with crypto enabled") orelse false;
    const disable_prints = b.option(bool, "disable_prints", "Do not print anything from uvgRTP") orelse false;
    const disable_werror = b.option(bool, "disable_werror", "Ignore compiler warnings") orelse true;
    const release_commit = b.option(bool, "release_commit", "Mark this as a release version in version prints") orelse false;

    const cryptopp_dep = if (!disable_crypto)
        b.lazyDependency("cryptopp", .{ .target = target, .optimize = optimize })
    else
        null;

    const mod = b.addModule("uvgRTP", .{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .root_source_file = b.path("uvgRTP.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "uvgRTP",
        .linkage = .static,
        .root_module = mod,
    });

    var flags_list = std.ArrayList([]const u8).empty;
    defer flags_list.deinit(b.allocator);

    try flags_list.appendSlice(b.allocator, &.{ "-Wall", "-Wextra", "-Wpedantic" });

    if (!disable_werror) {
        try flags_list.append(b.allocator, "-Werror");
    }
    if (disable_crypto) {
        try flags_list.append(b.allocator, "-D__RTP_NO_CRYPTO__");
    }
    if (disable_prints) {
        try flags_list.append(b.allocator, "-D__RTP_SILENT__");
    }

    const os_tag = target.result.os.tag;

    if (os_tag == .linux) {
        try flags_list.append(b.allocator, "-DUVGRTP_HAVE_GETRANDOM=1");
        try flags_list.append(b.allocator, "-DUVGRTP_HAVE_SENDMSG=1");
        try flags_list.append(b.allocator, "-DUVGRTP_HAVE_SENDMMSG=1");
    } else if (os_tag == .macos) {
        try flags_list.append(b.allocator, "-DUVGRTP_HAVE_SENDMSG=1");
    }

    const uvgrtp_flags = flags_list.items;

    const uvgrtp_sources = &[_][]const u8{
        "src/clock.cc",
        "src/crypto.cc",
        "src/frame.cc",
        "src/hostname.cc",
        "src/context.cc",
        "src/media_stream.cc",
        "src/mingw_inet.cc",
        "src/reception_flow.cc",
        "src/poll.cc",
        "src/frame_queue.cc",
        "src/random.cc",
        "src/rtcp.cc",
        "src/rtcp_packets.cc",
        "src/rtp.cc",
        "src/session.cc",
        "src/socket.cc",
        "src/zrtp.cc",
        "src/holepuncher.cc",
        "src/formats/media.cc",
        "src/formats/h26x.cc",
        "src/formats/h264.cc",
        "src/formats/h265.cc",
        "src/formats/h266.cc",
        "src/formats/v3c.cc",
        "src/zrtp/zrtp_receiver.cc",
        "src/zrtp/hello.cc",
        "src/zrtp/hello_ack.cc",
        "src/zrtp/commit.cc",
        "src/zrtp/dh_kxchng.cc",
        "src/zrtp/confirm.cc",
        "src/zrtp/confack.cc",
        "src/zrtp/error.cc",
        "src/zrtp/zrtp_message.cc",
        "src/srtp/base.cc",
        "src/srtp/srtp.cc",
        "src/srtp/srtcp.cc",
        "src/wrapper_c.cc",
        "src/socketfactory.cc",
        "src/rtcp_reader.cc",
    };

    lib.root_module.addCSourceFiles(.{
        .files = uvgrtp_sources,
        .flags = uvgrtp_flags,
        .language = .cpp,
    });

    const git_hash = getGitHash(b);
    const git_hash_str = git_hash orelse "source";

    const version_wf = b.addWriteFiles();
    _ = version_wf.add("version.cc", b.fmt(
        \\#include "uvgrtp/version.hh"
        \\
        \\#include <cstdint>
        \\#include <string>
        \\
        \\namespace uvgrtp {{
        \\
        \\#ifdef RTP_RELEASE_COMMIT
        \\    std::string get_version() {{ return "{s}-release"; }}
        \\#else
        \\    std::string get_version() {{ return "{s}-{s}"; }}
        \\#endif
        \\
        \\uint16_t get_version_major() {{ return {d}; }}
        \\
        \\uint16_t get_version_minor() {{ return {d}; }}
        \\
        \\uint16_t get_version_patch() {{ return {d}; }}
        \\
        \\std::string get_git_hash() {{return "{s}";}}
        \\}} // namespace uvgrtp
        \\
    , .{
        version_string,
        version_string,
        git_hash_str,
        version_major,
        version_minor,
        version_patch,
        git_hash_str,
    }));

    var version_flags_list = std.ArrayList([]const u8).empty;
    defer version_flags_list.deinit(b.allocator);

    if (release_commit) {
        try version_flags_list.append(b.allocator, "-DRTP_RELEASE_COMMIT");
    }

    lib.root_module.addCSourceFiles(.{
        .root = version_wf.getDirectory(),
        .files = &.{"version.cc"},
        .flags = version_flags_list.items,
        .language = .cpp,
    });

    lib.root_module.addIncludePath(b.path("include"));
    lib.root_module.addIncludePath(b.path("src"));

    if (cryptopp_dep) |dep| {
        lib.root_module.linkLibrary(dep.artifact("cryptopp"));
    }

    if (os_tag == .windows) {
        lib.root_module.linkSystemLibrary("wsock32", .{});
        lib.root_module.linkSystemLibrary("ws2_32", .{});
    } else if (os_tag == .macos) {
        lib.root_module.linkFramework("Security", .{});
    }

    lib.installHeadersDirectory(
        b.path("include/uvgrtp"),
        "uvgrtp",
        .{
            .include_extensions = &.{ ".hh", ".h" },
        },
    );

    // Builds examples if ran.
    const examples_step = b.step("examples", "Compile the examples");

    const io = b.graph.io;
    const examples = try std.Io.Dir.cwd().openDir(
        io,
        "examples",
        .{ .iterate = true },
    );
    var examples_iter = examples.iterateAssumeFirstIteration();

    const cryptopp = b.dependency(
        "cryptopp",
        .{ .target = target, .optimize = optimize },
    );

    while (true) {
        const ent = try examples_iter.next(io) orelse break;
        if (!std.mem.endsWith(u8, ent.name, ".zig")) continue;

        const example_name = ent.name[0 .. ent.name.len - 4];
        const example_source = b.fmt("examples/{s}", .{ent.name});

        // One file per example for now, might be a tad messy.
        const exe = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(example_source),
                .target = target,
                .optimize = optimize,
                .imports = &.{},
            }),
        });

        exe.root_module.link_libcpp = true;
        exe.root_module.link_libc = true;

        exe.root_module.linkLibrary(lib);
        exe.root_module.linkLibrary(cryptopp.artifact("cryptopp"));

        exe.root_module.addIncludePath(b.path("include"));

        const install_exe = b.addInstallArtifact(exe, .{});
        examples_step.dependOn(&install_exe.step);
    }

    b.installArtifact(lib);
}

fn getGitHash(b: *std.Build) ?[]const u8 {
    const result = std.process.run(
        b.allocator,
        b.graph.io,
        .{
            .argv = &.{ "git", "rev-parse", "--short", "HEAD" },
            .cwd = .inherit,
        },
    ) catch return null;

    if (result.term.exited != 0) return null;

    return std.mem.trimEnd(u8, result.stdout, "\r\n \t");
}
