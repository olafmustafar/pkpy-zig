const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("root", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const translate_c = b.addTranslateC(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.addWriteFiles().add("c.h",
            \\#define PK_IS_PUBLIC_INCLUDE
            \\#include "pocketpy.h"
            \\#undef PK_IS_PUBLIC_INCLUDE
        ),
    });

    translate_c.addIncludePath(b.path("3rd/pocketpy"));
    const c = translate_c.createModule();
    mod.addImport("pkpy_c", c);

    mod.addCSourceFiles(.{
        .files = &.{"3rd/pocketpy/pocketpy.c"},
        .language = .c,
    });

    mod.linkSystemLibrary("c", .{});
}
