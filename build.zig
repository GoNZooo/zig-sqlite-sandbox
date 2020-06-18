const Builder = @import("std").build.Builder;
const CrossTarget = @import("std").zig.CrossTarget;
const Abi = @import("std").Target.Abi;
const debug = @import("std").debug;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const gnu_target = CrossTarget{ .abi = Abi.gnu };
    const cross_target = b.standardTargetOptions(.{ .default_target = gnu_target });
    const exe = b.addExecutable("sqlite-sandbox", "src/main.zig");
    exe.linkLibC();
    exe.addCSourceFile(
        "./dependencies/sqlite-amalgamation-3310100/sqlite3.c",
        &[_][]const u8{},
    );
    exe.addIncludeDir("./dependencies/sqlite-amalgamation-3310100");
    exe.setBuildMode(mode);
    exe.setTarget(cross_target);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
