const std = @import("std");
const c = @import("pocketpy_c");

const Self = @This();

var context: ?*anyopaque = null;

const pk_bindings = [_]PocketpyTypeBinding{
    .init(c.tp_int, c.py_toint, c.py_newint, i64),
    .init(c.tp_float, c.py_tofloat, c.py_newfloat, f64),
    .init(c.tp_bool, c.py_tobool, c.py_newbool, bool),
    .init(c.tp_str, c.py_tostr, c.py_newstr, [*c]const u8),
};

pub fn init() Self {
    c.py_initialize();
    const builtins = c.py_getmodule("builtins");
    _ = c.py_deldict(builtins, c.py_name("exit"));
    return .{};
}

pub fn bindFunc(self: Self, comptime name: []const u8, comptime function: anytype) void {
    _ = self;
    const mod = c.py_getmodule("__main__");
    c.py_bindfunc(mod, @ptrCast(name), toPkpyFunction(function));
}

pub fn deinit(self: Self) void {
    _ = self;
    c.py_finalize();
}

pub fn eval(self: Self, ctx: ?*anyopaque, input: []const u8) void {
    _ = self;
    context = ctx;
    const p0: c.py_StackRef = c.py_peek(0);
    if (!c.py_eval(@ptrCast(input), null)) {
        c.py_printexc();
        c.py_clearexc(p0);
    }
}

const PocketpyTypeBinding = struct {
    pk_t: c.py_Type,
    cast_fn: *const anyopaque,
    create_fn: *const anyopaque,
    Type: type,
    const Self = @This();
    fn init(pk_t: c_int, cast_fn: *const anyopaque, create_fn: *const anyopaque, Type: type) @This() {
        return .{ .pk_t = pk_t, .cast_fn = cast_fn, .create_fn = create_fn, .Type = Type };
    }
};

fn castPk(T: type, val: c.py_Ref) T {
    inline for (pk_bindings) |t| if (t.Type == T) {
        const cast_fn: *const fn (c.py_Ref) callconv(.c) T = @ptrCast(t.cast_fn);
        return cast_fn(val);
    };
    @panic("Type not implemented");
}

fn createPk(out: c.py_OutRef, val: anytype) void {
    const T = @TypeOf(val);
    inline for (pk_bindings) |t| if (t.Type == T) {
        const create_fn: *const fn (c.py_OutRef, T) callconv(.c) void = @ptrCast(t.create_fn);
        create_fn(out, val);
        return;
    };
    @compileError("Type not implemented");
}

fn pktToType(pk_t: c_int) type {
    inline for (pk_bindings) |t| if (t.pk_t == pk_t) return t.Type;
    @compileError("Type not implemented");
}

fn typeToPkt(comptime T: type) c.py_Type {
    inline for (pk_bindings) |t| if (t.Type == T) return @intCast(t.pk_t);
    @compileError("Type not implemented");
}

fn toPkpyFunction(comptime function: anytype) c.py_CFunction {
    const Function = @TypeOf(function);
    const info = @typeInfo(Function).@"fn";
    const params = info.params[1..info.params.len];
    const Args = std.meta.ArgsTuple(Function);

    const gen = struct {
        fn gen(argc: c_int, argv: c.py_Ref) callconv(.c) bool {
            var args: Args = undefined;
            if (argc != params.len) return c.py_exception(c.tp_TypeError, "expected %d arguments, got %d", @as(c_int, args.len), argc);
            args[0] = context;
            inline for (params, 0..) |param, i| {
                if (!c.py_checktype(&argv[i], typeToPkt(param.type.?))) return false;
                args[i + 1] = castPk(@TypeOf(args[i + 1]), &argv[i]);
            }
            const res = @call(.auto, function, args);
            if (@TypeOf(res) == void) {
                c.py_newnone(c.py_retval());
            } else {
                createPk(c.py_retval(), res);
            }
            return true;
        }
    };
    return gen.gen;
}
