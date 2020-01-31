const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;

const ArrayList = std.ArrayList;

const c = @import("./c.zig");

const database_path = "../../javascript/project-manager/db/project-management.db";

const Employee = struct {
    const table = "employees";

    id: u32,
    name: []const u8,
    birthdate: []const u8,
    salary: u32,
    @"type": EmployeeType,

    pub fn allEmployees(
        allocator: *mem.Allocator,
        db: *c.sqlite3,
        bind_error: *BindErrorData,
    ) ![]Employee {
        const query = "SELECT id, name, birthdate, salary, type FROM " ++ table ++ ";";
        const statement = try prepareBind(db, query, &[_]Sqlite3Value{}, bind_error);
        const rows = try all(allocator, statement);
        var employees = try allocator.alloc(Employee, rows.len);
        for (rows) |row, i| {
            employees[i] = Employee{
                .id = @intCast(u32, row[0].I64),
                .name = row[1].Text,
                .birthdate = row[2].Text,
                .salary = @intCast(u32, row[3].I64),
                .type = try EmployeeType.fromString(row[4].Text),
            };
        }

        return employees;
    }
};

const EmployeeType = enum {
    BackendDeveloper,
    FrontendDeveloper,
    BedSleeper,

    pub fn fromString(string: []const u8) !EmployeeType {
        if (mem.eql(u8, string, "backend developer")) {
            return .BackendDeveloper;
        } else if (mem.eql(u8, string, "frontend developer")) {
            return .FrontendDeveloper;
        } else if (mem.eql(u8, string, "bed sleeper")) {
            return .BedSleeper;
        } else {
            debug.warn("Unrecognized employee type: {}\n", .{string});

            return error.InvalidEmployeeTypeFromString;
        }
    }
};

pub fn main() anyerror!void {
    var allocator = &heap.ArenaAllocator.init(heap.page_allocator).allocator;
    var maybe_db: ?*c.sqlite3 = undefined;
    const open_result = c.sqlite3_open_v2(
        database_path,
        &maybe_db,
        c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE,
        null,
    );
    if (open_result != c.SQLITE_OK or maybe_db == null) {
        debug.panic("Unable to open database '{}'\n", .{database_path});
    }
    const db = maybe_db.?;
    defer _ = c.sqlite3_close(db);

    var bind_error: BindErrorData = undefined;
    const employees = try Employee.allEmployees(allocator, db, &bind_error);
    for (employees) |e| {
        debug.warn("e={}\n", .{e});
    }

    // const query: []const u8 = "SELECT name, salary FROM employees WHERE salary < ?;";
    // const values = &[_]Sqlite3Value{.{ .I64 = 2000 }};
    // var bind_error: BindErrorData = undefined;
    // const statement = prepareBind(db, query, values, &bind_error) catch |e| {
    //     switch (e) {
    //         error.BindError => {
    //             debug.panic("Bind error on value: {}\n", .{bind_error});
    //         },
    //         error.NullStatement => {
    //             debug.panic("Prepare error\n", .{});
    //         },
    //     }
    // };
    // try execute(statement);
    // const row = try one(allocator, statement);
    // for (row) |v| {
    //     debug.warn("v={}\n", .{v});
    // }

    // const rows = try all(allocator, statement);
}

fn prepareBind(
    db: *c.sqlite3,
    query: []const u8,
    values: []Sqlite3Value,
    bind_error: *BindErrorData,
) !*c.sqlite3_stmt {
    const statement = try prepare(db, query);
    try bind(statement, values, bind_error);

    return statement;
}

fn prepare(db: *c.sqlite3, query: []const u8) !*c.sqlite3_stmt {
    var maybe_statement: ?*c.sqlite3_stmt = undefined;
    _ = c.sqlite3_prepare_v3(db, query.ptr, @intCast(c_int, query.len), 0, &maybe_statement, null);
    if (maybe_statement == null) return error.NullStatement;

    return maybe_statement.?;
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

const BindErrorData = union(enum) {
    BindError: Sqlite3Value,
};

fn bind(statement: *c.sqlite3_stmt, values: []Sqlite3Value, maybe_error: *BindErrorData) !void {
    const statement_columns = c.sqlite3_column_count(statement);
    var column: usize = 1;
    for (values) |v| {
        switch (v) {
            .I64 => |i64Value| {
                if (c.sqlite3_bind_int64(
                    statement,
                    @intCast(c_int, column),
                    i64Value,
                ) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .Text => |text| {
                if (c.sqlite3_bind_text(
                    statement,
                    @intCast(c_int, column),
                    text.ptr,
                    @intCast(c_int, text.len),
                    doNothing,
                ) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .Blob => |blob| {
                if (c.sqlite3_bind_blob(
                    statement,
                    @intCast(c_int, column),
                    if (blob) |b| b.ptr else null,
                    if (blob) |b| @intCast(c_int, b.len) else 0,
                    doNothing,
                ) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .F64 => |f64Value| {
                if (c.sqlite3_bind_double(
                    statement,
                    @intCast(c_int, column),
                    f64Value,
                ) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .Null => {
                if (c.sqlite3_bind_null(statement, @intCast(c_int, column)) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
        }
        column += 1;
    }
}

fn execute(statement: *c.sqlite3_stmt) !void {
    const step_result = c.sqlite3_step(statement);
    switch (step_result) {
        c.SQLITE_DONE => {},
        c.SQLITE_BUSY => return error.Sqlite3Busy,
        else => debug.panic("Unrecognized error: {}\n", .{step_result}),
    }
    if (step_result != c.SQLITE_DONE) return error.StepError;
    const finalize_result = c.sqlite3_finalize(statement);
    if (finalize_result != c.SQLITE_OK) return error.FinalizeError;
}

fn one(allocator: *mem.Allocator, statement: *c.sqlite3_stmt) !Row {
    defer _ = c.sqlite3_finalize(statement);

    const step_result = c.sqlite3_step(statement);
    switch (step_result) {
        c.SQLITE_DONE => return error.OneDoneWithoutRow,
        c.SQLITE_ERROR => return error.OneError,
        c.SQLITE_ROW => {
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

            return row;
        },
        else => debug.panic("Unhandled `step` return value: {}\n", .{step_result}),
    }
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
