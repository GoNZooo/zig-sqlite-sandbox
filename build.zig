const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("sqlite-sandbox", "src/main.zig");
    exe.linkLibC();
    exe.addIncludeDir("./dependencies/sqlite-amalgamation-3310100");
    exe.addLibPath("./dependencies/sqlite-amalgamation-3310100");
    exe.linkSystemLibrary("sqlite3");
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
