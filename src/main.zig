const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;

const ArrayList = std.ArrayList;

const c = @import("./c.zig");

const database_path = "../../javascript/project-manager/db/project-management.db";

pub fn main() anyerror!void {
    var allocator = &heap.ArenaAllocator.init(heap.page_allocator).allocator;
    var db: ?*c.sqlite3 = undefined;
    const open_result = c.sqlite3_open_v2(
        database_path,
        &db,
        c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
        null,
    );
    if (open_result != c.SQLITE_OK) {
        debug.warn("Unable to open database '{}'\n", .{database_path});
    }

    const file: []const u8 = &[_]u8{ 'w', 't', 'f' };

    // const query: []const u8 = "INSERT INTO things (thing_1) VALUES (?);";
    const query: []const u8 = "SELECT * FROM things;";
    var maybe_statement: ?*c.sqlite3_stmt = undefined;
    _ = c.sqlite3_prepare_v3(db, query.ptr, @intCast(c_int, query.len), 0, &maybe_statement, null);
    if (maybe_statement == null) return error.NullStatement;
    var statement = maybe_statement.?;

    // const bind_result = c.sqlite3_bind_blob(
    //     statement,
    //     1,
    //     file.ptr,
    //     file.len,
    //     doNothing,
    // );
    // debug.warn("bind_result={}\n", .{bind_result});
    // try execute(statement);

    const rows = try all(allocator, statement);
    for (rows) |row| {
        for (row) |v| {
            debug.warn("v={} ", .{v});
        }
        debug.warn("\n", .{});
    }

    _ = c.sqlite3_close(db);
}

extern fn doNothing(data: ?*c_void) void {}

const Sqlite3Value = union(enum) {
    Text: []const u8,
    Blob: ?[]const u8,
    // it's up to the user of the value to cast this integer type into something appropriate
    I64: i64,
    F64: f64,
    Null: void,
};

const Row = []Sqlite3Value;

fn execute(statement: *c.sqlite3_stmt) !void {
    const step_result = c.sqlite3_step(statement);
    if (step_result != c.SQLITE_DONE) return error.StepError;
    const finalize_result = c.sqlite3_finalize(statement);
    debug.warn("finalize_result={}\n", .{finalize_result});
}

fn all(allocator: *mem.Allocator, statement: *c.sqlite3_stmt) ![]const []Sqlite3Value {
    var rows = ArrayList([]Sqlite3Value).init(allocator);
    defer _ = c.sqlite3_finalize(statement);

    var step_result = c.sqlite3_step(statement);
    while (step_result != c.SQLITE_DONE and step_result != c.SQLITE_ERROR) : (step_result = c.sqlite3_step(statement)) {
        const columns = c.sqlite3_column_count(statement);
        var row = try allocator.alloc(Sqlite3Value, @intCast(usize, columns));
        var current_column: c_int = 0;
        while (current_column < columns) : (current_column += 1) {
            const column_type = c.sqlite3_column_type(statement, current_column);
            const value = value: {
                break :value switch (column_type) {
                    c.SQLITE_INTEGER => Sqlite3Value{
                        .I64 = c.sqlite3_column_int64(statement, current_column),
                    },
                    c.SQLITE_FLOAT => Sqlite3Value{
                        .F64 = c.sqlite3_column_double(statement, current_column),
                    },
                    c.SQLITE_TEXT => {
                        const content = c.sqlite3_column_text(statement, current_column);
                        const size = @intCast(usize, c.sqlite3_column_bytes(
                            statement,
                            current_column,
                        ));
                        var text = try allocator.alloc(u8, size);
                        var content_pointer = content;
                        var index: usize = 0;
                        while (content_pointer.* != 0) : (content_pointer += 1) {
                            text[index] = content_pointer.*;
                            index += 1;
                        }

                        break :value Sqlite3Value{ .Text = text };
                    },
                    c.SQLITE_BLOB => {
                        const content = @ptrCast(?[*]const u8, c.sqlite3_column_blob(
                            statement,
                            current_column,
                        )) orelse break :value Sqlite3Value{ .Blob = null };
                        const size = @intCast(usize, c.sqlite3_column_bytes(
                            statement,
                            current_column,
                        ));
                        var blob = try allocator.alloc(u8, size);
                        var content_pointer = content;
                        var index: usize = 0;
                        while (content_pointer[index] != 0) : (index += 1) {
                            blob[index] = content_pointer[index];
                        }

                        break :value Sqlite3Value{ .Blob = blob };
                    },
                    c.SQLITE_NULL => Sqlite3Value{ .Null = undefined },
                    else => debug.panic("unsupported type: {}\n", .{column_type}),
                };
            };
            row[@intCast(usize, current_column)] = value;
        }
        try rows.append(row);
    }

    return rows.toSliceConst();
}
