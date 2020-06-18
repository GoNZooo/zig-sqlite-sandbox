const std = @import("std");
const debug = std.debug;
const mem = std.mem;
const heap = std.heap;
const fmt = std.fmt;

const ArrayList = std.ArrayList;

const c = @import("./c.zig");

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
    var employee = try Employee.getOneById(allocator, db, &bind_error, 4);
    debug.warn("employee={}\n", .{employee});
    employee.salary = 1000;
    try employee.update(db, &bind_error);
    const employees = try Employee.getAll(allocator, db, &bind_error);
    for (employees) |e| {
        debug.warn("e={}\n", .{e});
    }
    const thing = Thing{ .thing1 = null };
    const things = try Thing.allThings(allocator, db, &bind_error);
    for (things) |t| {
        debug.warn("t={}\n", .{t});
    }
}

// @TODO: create Sqlite3Context?

const Employee = struct {
    const table = "employees";

    id: u32,
    name: []const u8,
    birthdate: []const u8,
    salary: u32,
    @"type": EmployeeType,

    pub fn getAll(
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
                .id = @intCast(u32, try row[0].getI64()),
                .name = try row[1].getText(),
                .birthdate = try row[2].getText(),
                .salary = @intCast(u32, try row[3].getI64()),
                .type = try EmployeeType.fromString(try row[4].getText()),
            };
        }

        return employees;
    }

    pub fn getOneById(
        allocator: *mem.Allocator,
        db: *c.sqlite3,
        bind_error: *BindErrorData,
        id: i64,
    ) !Employee {
        const query = "SELECT id, name, birthdate, salary, type FROM " ++ table ++ " WHERE id = ?;";
        const statement = try prepareBind(db, query, &[_]Sqlite3Value{.{ .I64 = id }}, bind_error);
        const row = try one(allocator, statement);
        const employee = Employee{
            .id = @intCast(u32, try row[0].getI64()),
            .name = try row[1].getText(),
            .birthdate = try row[2].getText(),
            .salary = @intCast(u32, try row[3].getI64()),
            .type = try EmployeeType.fromString(try row[4].getText()),
        };

        return employee;
    }

    pub fn update(self: Employee, db: *c.sqlite3, bind_error: *BindErrorData) !void {
        const query = "UPDATE " ++ table ++
            " SET name = ?, birthdate = ?, salary = ?, type = ? WHERE id = ?;";
        const statement = try prepareBind(
            db,
            query,
            &[_]Sqlite3Value{
                .{ .Text = self.name },
                .{ .Text = self.birthdate },
                .{ .I64 = @intCast(i64, self.salary) },
                .{ .Text = self.@"type".toString() },
                .{ .I64 = self.id },
            },
            bind_error,
        );
        try execute(statement);
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

    pub fn toString(self: EmployeeType) []const u8 {
        return switch (self) {
            .BackendDeveloper => "backend developer",
            .FrontendDeveloper => "frontend developer",
            .BedSleeper => "bed sleeper",
        };
    }
};

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

fn doNothing(data: ?*c_void) callconv(.C) void {}

const Sqlite3Value = union(enum) {
    Text: []const u8,
    Blob: ?[]const u8,
    // it's up to the user of the value to cast this integer type into something appropriate
    I64: i64,
    F64: f64,
    Null: void,

    pub fn getI64(self: Sqlite3Value) !i64 {
        return switch (self) {
            .I64 => |i64Value| i64Value,
            else => error.NonI64ValueGet,
        };
    }

    pub fn getI64OrNull(self: Sqlite3Value) !?i64 {
        return switch (self) {
            .I64 => |i64Value| i64Value,
            .Null => null,
            else => error.NonI64ValueGet,
        };
    }

    pub fn getF64(self: Sqlite3Value) !f64 {
        return switch (self) {
            .F64 => |f64Value| f64Value,
            else => error.NonF64ValueGet,
        };
    }

    pub fn getF64OrNull(self: Sqlite3Value) !?f64 {
        return switch (self) {
            .F64 => |f64Value| f64Value,
            .Null => null,
            else => error.NonF64ValueGet,
        };
    }

    pub fn getText(self: Sqlite3Value) ![]const u8 {
        return switch (self) {
            .Text => |text| text,
            else => error.NonTextValueGet,
        };
    }

    pub fn getTextOrNull(self: Sqlite3Value) !?[]const u8 {
        return switch (self) {
            .Text => |text| text,
            .Null => null,
            else => error.NonTextValueGet,
        };
    }

    pub fn getBlob(self: Sqlite3Value) ![]const u8 {
        return switch (self) {
            .Blob => |blob| blob.?,
            else => error.NonBlobValueGet,
        };
    }

    pub fn getBlobOrNull(self: Sqlite3Value) !?[]const u8 {
        return switch (self) {
            .Blob => |blob| blob,
            .Null => null,
            else => error.NonBlobValueGet,
        };
    }

    pub fn getNull(self: Sqlite3Value) !?void {
        return switch (self) {
            .Null => null,
            else => error.NonNullValueGet,
        };
    }
};

const Thing = struct {
    const table = "things";

    thing1: ?[]const u8,

    pub fn insert(self: Thing, db: *c.sqlite3, bind_error: *BindErrorData) !void {
        const query = "INSERT INTO " ++ table ++ "(thing_1) VALUES (?);";
        const statement = try prepareBind(
            db,
            query,
            &[_]Sqlite3Value{.{ .Blob = self.thing1 }},
            bind_error,
        );
        try execute(statement);
    }

    pub fn allThings(
        allocator: *mem.Allocator,
        db: *c.sqlite3,
        bind_error: *BindErrorData,
    ) ![]Thing {
        const query = "SELECT (thing_1) FROM " ++ table ++ ";";
        const statement = try prepareBind(db, query, &[_]Sqlite3Value{}, bind_error);
        const rows = try all(allocator, statement);
        var things = try allocator.alloc(Thing, rows.len);
        for (rows) |row, i| {
            things[i] = Thing{ .thing1 = try row[0].getBlobOrNull() };
        }

        return things;
    }
};

const Row = []Sqlite3Value;

const BindErrorData = union(enum) {
    BindError: Sqlite3Value,
};

fn bind(statement: *c.sqlite3_stmt, values: []Sqlite3Value, maybe_error: *BindErrorData) !void {
    const bind_parameter_count = c.sqlite3_bind_parameter_count(statement);
    debug.assert(bind_parameter_count == values.len);

    var column: c_int = 1;
    for (values) |v| {
        switch (v) {
            .I64 => |i64Value| {
                if (c.sqlite3_bind_int64(statement, column, i64Value) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .Text => |text| {
                if (c.sqlite3_bind_text(
                    statement,
                    column,
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
                    column,
                    if (blob) |b| b.ptr else null,
                    if (blob) |b| @intCast(c_int, b.len) else 0,
                    doNothing,
                ) != c.SQLITE_OK) {
                    maybe_error.* = BindErrorData{ .BindError = v };

                    return error.BindError;
                }
            },
            .F64 => |f64Value| {
                if (c.sqlite3_bind_double(statement, column, f64Value) != c.SQLITE_OK) {
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
    while (step_result != c.SQLITE_DONE and
        step_result != c.SQLITE_ERROR) : (step_result = c.sqlite3_step(statement))
    {
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

    return rows.items;
}

const database_path = "../../javascript/project-manager/db/project-management.db";
