const builtin = @import("builtin");

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Progress = std.Progress;
const Random = std.Random;

const Vec3 = @import("Vec3.zig");
const Vec2 = @import("Vec2.zig");
const Ray = @import("Ray.zig");
const Color = @import("Color.zig");

const objects = @import("objects.zig");
const Hit = objects.Hit;

const Self = @This();

pub const Options = struct {
    /// Ratio of image width over height
    aspect_ratio: f64 = 16.0 / 9.0,
    /// Rendered image width in pixel count
    img_dim: ImgDim = .{ .width = 1920 },

    /// Count of random samples for each pixel
    samples_per_pixel: u16 = 100,
    /// Maximum number of ray bounces into scene
    max_depth: u16 = 50,

    /// Vertical view angle (field of view)
    v_fov: f64 = 90,

    /// Point camera is looking from
    look_from: Vec3 = .zero,
    /// Point camera is looking at
    look_at: Vec3 = .neg_z_axis,

    /// Camera-relative "up" direction
    up: Vec3 = .y_axis,

    /// Variation angle of rays through each pixel
    defocus_angle: f64 = 0,
    /// Distance from camera lookfrom point to plane of perfect focus
    focus_dist: f64 = 10,
};

pub const ImgDim = union(enum) {
    width: u32,
    height: u32,
};

aspect_ratio: f64,
img_width: u32,
img_height: u32,
samples_per_pixel: u16,
max_depth: usize,
look_from: Vec3,
defocus_angle: f64,
defocus_disk_u: Vec3,
defocus_disk_v: Vec3,
pixel_delta_u: Vec3,
pixel_delta_v: Vec3,
pixel00_loc: Vec3,

pub fn init(options: Options) Self {
    const img_width, const img_height = switch (options.img_dim) {
        .width => |img_width| blk: {
            const fwidth: f64 = @floatFromInt(img_width);
            const h: u32 = @intFromFloat(fwidth / options.aspect_ratio);
            break :blk .{ img_width, if (h < 1) 1 else h };
        },
        .height => |img_height| blk: {
            const fheight: f64 = @floatFromInt(img_height);
            const w: u32 = @intFromFloat(fheight * options.aspect_ratio);
            break :blk .{ w, img_height };
        },
    };

    const viewport_height = blk: {
        const theta = std.math.degreesToRadians(options.v_fov);
        const h = std.math.tan(theta / 2.0);
        break :blk 2 * h * options.focus_dist;
    };
    const viewport_width = blk: {
        const fwidth: f64 = @floatFromInt(img_width);
        const fheight: f64 = @floatFromInt(img_height);
        break :blk viewport_height * (fwidth / fheight);
    };

    // Camera frame basis Z axis
    const w: Vec3 = options.look_from.sub(options.look_at).normalized();
    // Camera frame basis X axis
    const u: Vec3 = options.up.cross(w).normalized();
    // Camera frame basis Y axis
    const v: Vec3 = w.cross(u);

    const defocus_radius = options.focus_dist * std.math.tan(std.math.degreesToRadians(options.defocus_angle / 2.0));
    // Defocus disk horizontal radius
    const defocus_disk_u: Vec3 = u.mulScalar(defocus_radius);
    // Defocus disk vertical radius
    const defocus_disk_v: Vec3 = v.mulScalar(defocus_radius);

    // Vector across viewport horizontal edge
    const viewport_u = u.mulScalar(viewport_width);
    // Vector down viewport vertical edge
    const viewport_v = v.neg().mulScalar(viewport_height);

    // Offset to pixel to the right
    const pixel_delta_u: Vec3 = viewport_u.divScalar(@floatFromInt(img_width));
    // Offset to pixel below
    const pixel_delta_v: Vec3 = viewport_v.divScalar(@floatFromInt(img_height));

    // Location of pixel (0, 0)
    const pixel00_loc: Vec3 = blk: {
        const viewport_upper_left: Vec3 = options.look_from
            .sub(w.mulScalar(options.focus_dist))
            .sub(viewport_u.divScalar(2))
            .sub(viewport_v.divScalar(2));
        break :blk pixel_delta_u.add(pixel_delta_v).mulScalar(0.5).add(viewport_upper_left);
    };

    return .{
        .aspect_ratio = options.aspect_ratio,
        .img_width = img_width,
        .img_height = img_height,
        .samples_per_pixel = options.samples_per_pixel,
        .max_depth = options.max_depth,
        .look_from = options.look_from,
        .defocus_angle = options.defocus_angle,
        .defocus_disk_u = defocus_disk_u,
        .defocus_disk_v = defocus_disk_v,
        .pixel_delta_u = pixel_delta_u,
        .pixel_delta_v = pixel_delta_v,
        .pixel00_loc = pixel00_loc,
    };
}

pub fn render(
    self: *const Self,
    allocator: Allocator,
    image_path: []const u8,
    world: anytype,
) !void {
    const file = try std.fs.cwd().createFile(image_path, .{
        .read = true,
        .truncate = false,
        .exclusive = false,
    });
    defer file.close();

    const header_format = "P6\n{d} {d}\n255\n";
    var buf: [std.fmt.count(header_format, .{std.math.maxInt(u32)} ** 2)]u8 = undefined;
    const header: []const u8 = try std.fmt.bufPrint(&buf, header_format, .{ self.img_width, self.img_height });

    const size = header.len + self.img_width * self.img_height * 3;
    try file.setEndPos(size);

    if (builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
        const metadata = try file.metadata();
        assert(metadata.size() == size);
    }

    const mapping = try mmapImageFile(file, size);
    defer munmapImageFile(mapping);

    const ptr = mapping.getPtr();

    @memcpy(ptr[0..header.len], header);
    const image = std.mem.bytesAsSlice([3]u8, ptr[header.len..]);

    // const image = try allocator.alloc(Color, img_width * img_height);
    // defer allocator.free(image);
    // @memset(image, .{0} ** 3);

    const grid = try self.factorizeParallelizm();
    std.log.debug("grid: {d}x{d} WxH", .{ grid.width, grid.height });

    const progress = Progress.start(.{
        .estimated_total_items = grid.height * grid.width * grid.height * grid.width,
        .root_name = "rendering",
    });

    defer progress.end();
    var task_queue: TaskQueue(kernel) = undefined;
    try task_queue.init(allocator, grid.height * grid.height * grid.width * grid.width);
    errdefer task_queue.abort(allocator);

    const whole_image_grid_cell_width = self.img_width / (grid.width * grid.width);
    const remainder_image_grid_cell_width = self.img_width % (grid.width * grid.width);
    const whole_image_grid_cell_height = self.img_height / (grid.height * grid.height);
    const remainder_image_grid_cell_height = self.img_height % (grid.height * grid.height);
    for (0..grid.height * grid.height) |i| {
        for (0..grid.width * grid.width) |j| {
            const kernel_x = j * (whole_image_grid_cell_width + @intFromBool(j < remainder_image_grid_cell_width + 1));
            const kernel_y = i * (whole_image_grid_cell_height + @intFromBool(i < remainder_image_grid_cell_height + 1));

            const kernel_width = whole_image_grid_cell_width + @intFromBool(j < remainder_image_grid_cell_width);
            const kernel_height = whole_image_grid_cell_height + @intFromBool(i < remainder_image_grid_cell_height);

            try task_queue.addTask(allocator, .{
                .args = .{
                    self,
                    kernel_x,
                    kernel_y,
                    kernel_width,
                    kernel_height,
                    world,
                    image,
                    progress,
                },
            });
        }
    }

    task_queue.runToCompletion(allocator);
}

fn factorizeParallelizm(self: *const Self) !struct { width: Sqrt(usize), height: Sqrt(usize) } {
    const parallelizm: usize = try Thread.getCpuCount();

    const dim_a: Sqrt(usize) = std.math.sqrt(parallelizm);
    const dim_b: Sqrt(usize) = @intCast(try std.math.divExact(usize, parallelizm, dim_a));

    return .{
        .width = if (self.aspect_ratio > 1) dim_b else dim_a,
        .height = if (self.aspect_ratio > 1) dim_a else dim_b,
    };
}

fn Sqrt(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int => |info| std.meta.Int(.unsigned, (info.bits + 1) / 2),
        else => T,
    };
}

fn kernel(
    self: *const Self,
    kx: usize,
    ky: usize,
    kw: usize,
    kh: usize,
    world: []const objects.Sphere,
    image: [][3]u8,
    progress: std.Progress.Node,
) void {
    const fmt = "T: {d}; x: {d}, y: {d}, w: {d}, h: {d}";
    var name_buf: [std.fmt.count(fmt, .{std.math.maxInt(Thread.Id)} ++ .{std.math.maxInt(usize)} ** 4)]u8 = undefined;
    const name: []const u8 = std.fmt.bufPrint(&name_buf, fmt, .{ Thread.getCurrentId(), kx, ky, kw, kh }) catch unreachable;

    const kprogress = progress.start(name, kw * kh * self.samples_per_pixel);
    defer kprogress.end();

    const rand = @import("rnd.zig").random();

    for (kx..kx + kw) |x| {
        for (ky..ky + kh) |y| {
            var pixel: Color = .black;
            for (0..self.samples_per_pixel) |_| {
                const ray: Ray = self.getRay(
                    rand,
                    @floatFromInt(x),
                    @floatFromInt(y),
                );
                pixel.v += self.rayColor(ray, rand, world).v;

                kprogress.completeOne();
            }
            pixel.v /= @splat(@floatFromInt(self.samples_per_pixel));

            var pixel_bytes: [3]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&pixel_bytes);
            std.fmt.format(fbs.writer().any(), "{}", .{pixel}) catch unreachable;
            image[y * self.img_width + x] = pixel_bytes;
        }
    }
}

fn getRay(self: *const Self, rand: Random, x: f64, y: f64) Ray {
    // const offset = sampleSquare(rand);
    const offset = samleGausian(rand);
    const pixel_sample = self.pixel_delta_v.mulScalarAdd(
        y + offset.y(),
        self.pixel_delta_u.mulScalarAdd(
            x + offset.x(),
            self.pixel00_loc,
        ),
    );

    const ray_origin = if (self.defocus_angle <= 0)
        self.look_from
    else
        self.defocusDiskScample(rand);

    const ray_dir: Vec3 = pixel_sample.sub(ray_origin);

    return .init(ray_origin, ray_dir);
}

fn sampleSquare(rand: Random) Vec2 {
    return .init(.{
        rand.float(f64) - 0.5,
        rand.float(f64) - 0.5,
    });
}

fn samleGausian(rand: Random) Vec2 {
    return .init(.{
        rand.floatNorm(f64),
        rand.floatNorm(f64),
    });
}

fn defocusDiskScample(self: *const Self, rand: Random) Vec3 {
    const p: Vec2 = .randomUnit(rand);
    return self.defocus_disk_u.mulScalarAdd(
        p.x(),
        self.defocus_disk_v.mulScalarAdd(
            p.y(),
            self.look_from,
        ),
    );
}

fn rayColor(
    self: *const Self,
    ray: Ray,
    rand: Random,
    world: anytype,
) Color {
    var ray_ = ray;
    var depth: @TypeOf(self.max_depth) = 0;

    var product: Color = .white;
    while (depth < self.max_depth) : (depth += 1) {
        if (hitWorld(world, ray_)) |hit| {
            if (hit.material.scatter(rand, ray_, hit)) |scatter| {
                ray_ = scatter.scattered_ray;
                product.mulAssign(scatter.attenuation);
            } else return .black;
        } else {
            const unit_direction = ray_.dir.normalized();
            const a: f64 = 0.5 * (unit_direction.y() + 1.0);
            const wat: Color = .init(.{ 0.5, 0.7, 1 });
            product.mulAssign(wat.mulScalarAdd(a, .splat(1.0 - a)));
            break;
        }
    }

    return product;
}

fn hitWorld(objs: anytype, ray: Ray) ?Hit {
    var hit: ?Hit = null;
    var closest_so_far = std.math.inf(f64);
    for (objs) |obj| {
        if (obj.hit(ray, .{ .min = 0.001, .max = closest_so_far })) |h| {
            hit = h;
            closest_so_far = hit.?.t;
        }
    }
    return hit;
}

fn TaskQueue(comptime func: anytype) type {
    return struct {
        mutex: Mutex = .{},
        tasks: Tasks = .empty,
        run_to_exhaustion: AtomicBool = .init(false),
        run: AtomicBool = .init(true),
        threads: []Thread,

        const Mutex = std.Thread.Mutex;
        const AtomicBool = std.atomic.Value(bool);
        const Tasks = std.ArrayListUnmanaged(Task(func));

        pub fn init(self: *@This(), allocator: Allocator, tasks_cap: ?usize) !void {
            const parallelism = try Thread.getCpuCount();
            const threads = try allocator.alloc(Thread, parallelism);

            self.* = .{ .threads = threads };
            if (tasks_cap) |cap| {
                self.tasks = try Tasks.initCapacity(allocator, cap);
            }

            std.log.debug("Parallelism: {d}", .{parallelism});
            for (0..parallelism) |i| {
                std.log.debug("Starting thread {d}", .{i});
                threads[i] = try Thread.spawn(
                    .{ .allocator = allocator },
                    struct {
                        fn f(
                            tasks: *Tasks,
                            mutex: *Mutex,
                            run: *const AtomicBool,
                            run_to_exhaustion: *const AtomicBool,
                        ) Task(func).Return {
                            while (run.load(.acquire)) {
                                if (mutex.tryLock()) {
                                    const maybe_task = blk: {
                                        defer mutex.unlock();
                                        break :blk tasks.pop();
                                    };
                                    const err_msg = "expected func to return `void` or `!void`, but was `" ++ @typeName(Task(func).Return) ++ "`";
                                    if (maybe_task) |task| switch (@typeInfo(Task(func).Return)) {
                                        .void => task.run(),
                                        .error_union => |eu| if (eu.payload == void)
                                            try task.run()
                                        else
                                            @compileError(err_msg),
                                        else => @compileError(err_msg),
                                    } else if (run_to_exhaustion.load(.acquire)) break;
                                }
                            }
                        }
                    }.f,
                    .{
                        &self.tasks,
                        &self.mutex,
                        &self.run,
                        &self.run_to_exhaustion,
                    },
                );
            }
        }

        pub fn addTask(self: *@This(), allocator: Allocator, task: Task(func)) !void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.tasks.append(allocator, task);
        }

        pub fn addTaskAssumeCapacity(self: *@This(), task: Task(func)) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.tasks.appendAssumeCapacity(task);
        }

        pub fn runToCompletion(self: *@This(), allocator: Allocator) void {
            defer allocator.free(self.threads);
            self.run_to_exhaustion.store(true, .release);
            for (self.threads) |thread| {
                thread.join();
            }
        }

        pub fn abort(self: *@This(), allocator: Allocator) void {
            defer allocator.free(self.threads);
            self.run.store(false, .release);
            for (self.threads) |thread| {
                thread.join();
            }
        }
    };
}

fn Task(comptime func: anytype) type {
    const Fn = @TypeOf(func);
    return struct {
        args: Args,

        pub const Args = std.meta.ArgsTuple(@TypeOf(func));
        pub const Return = switch (@typeInfo(Fn)) {
            .@"fn" => |info| info.return_type.?,
            else => @compileError("Expected `func` to be a function"),
        };

        fn run(self: @This()) Return {
            return @call(.auto, func, self.args);
        }
    };
}

const MmapResult = switch (builtin.os.tag) {
    .wasi => @compileError("unsupported"),
    .windows => struct {
        ptr: []u8,
        file_mapping: std.os.windows.HANDLE,

        inline fn getPtr(self: @This()) []u8 {
            return self.ptr;
        }
    },
    else => struct {
        ptr: []align(std.heap.page_size_min) u8,

        inline fn getPtr(self: @This()) []align(std.heap.page_size_min) u8 {
            return self.ptr;
        }
    },
};

fn mmapImageFile(file: std.fs.File, size: usize) !MmapResult {
    return switch (builtin.os.tag) {
        .windows => blk: {
            const windows = @import("windows.zig");
            const DWORD = windows.DWORD;
            const CreateFileMapping = windows.CreateFileMappingA;
            const MapViewOfFile = windows.MapViewOfFile;
            const CloseHandle = windows.CloseHandle;

            const file_mapping: windows.HANDLE = CreateFileMapping(
                file.handle,
                null,
                .PAGE_READWRITE,
                @as(DWORD, @intCast(size >> 32)),
                @as(DWORD, @intCast(size & std.math.maxInt(DWORD))),
                null,
            ) orelse {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to create file mapping ({d})", .{@intFromEnum(err)});
                break :blk error.FileMappingFailed;
            };
            errdefer CloseHandle(file_mapping);

            const ptr = MapViewOfFile(
                file_mapping,
                windows.FILE_MAP_ALL_ACCESS,
                0,
                0,
                size,
            ) orelse {
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to map view of file ({d})", .{@intFromEnum(err)});
                break :blk error.FileMappingFailed;
            };

            const many_ptr: [*]u8 = @ptrCast(ptr);
            return .{
                .ptr = many_ptr[0..size],
                .file_mapping = file_mapping,
            };
        },
        else => .{ .ptr = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) },
    };
}

fn munmapImageFile(mmap_result: MmapResult) void {
    switch (builtin.os.tag) {
        .wasi => @compileError("unsupported"),
        .windows => {
            const windows = @import("windows.zig");
            const UnmapViewOfFile = windows.UnmapViewOfFile;
            const FlushViewOfFile = windows.FlushViewOfFile;
            const CloseHandle = windows.CloseHandle;

            const ptr, const file_mapping = .{ mmap_result.ptr, mmap_result.file_mapping };

            if (UnmapViewOfFile(ptr.ptr) == 0) {
                @branchHint(.cold);
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to unmap view of file ({d})", .{@intFromEnum(err)});
                return;
            }

            if (FlushViewOfFile(ptr.ptr, 0) == 0) {
                @branchHint(.cold);
                const err = std.os.windows.GetLastError();
                std.log.err("Failed to flush view of file ({d})", .{@intFromEnum(err)});
                return;
            }
            CloseHandle(file_mapping);
        },
        else => std.posix.munmap(mmap_result.ptr),
    }
}
