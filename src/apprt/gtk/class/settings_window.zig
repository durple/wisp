const std = @import("std");
const adw = @import("adw");
const gobject = @import("gobject");
const gtk = @import("gtk");

const gresource = @import("../build/gresource.zig");
const i18n = @import("../../../os/main.zig").i18n;
const Common = @import("../class.zig").Common;
const Application = @import("application.zig").Application;
const schema_mod = @import("../../../config/schema.zig");

const log = std.log.scoped(.gtk_ghostty_settings_window);

pub const SettingsWindow = extern struct {
    const Self = @This();
    parent_instance: Parent,
    pub const Parent = adw.PreferencesWindow;
    pub const getGObjectType = gobject.ext.defineClass(Self, .{
        .name = "GhosttySettingsWindow",
        .instanceInit = &init,
        .classInit = &Class.init,
        .parent_class = &Class.parent,
        .private = .{ .Type = Private, .offset = &Private.offset },
    });

    const Private = struct {
        pub var offset: c_int = 0;
    };

    fn init(self: *Self, _: *Class) callconv(.c) void {
        gtk.Widget.initTemplate(self.as(gtk.Widget));
    }

    fn dispose(self: *Self) callconv(.c) void {
        gtk.Widget.disposeTemplate(self.as(gtk.Widget), getGObjectType());
        gobject.Object.virtual_methods.dispose.call(Class.parent, self.as(Parent));
    }

    /// Open a settings window and present it to the user.
    pub fn open() void {
        const app = Application.default();
        const win = gobject.ext.newInstance(Self, .{});

        // Register with our AdwApplication so the window is properly themed
        // and tracked.
        gtk.Window.setApplication(
            win.as(gtk.Window),
            app.as(gtk.Application),
        );

        win.buildPages(app);

        gtk.Window.present(win.as(gtk.Window));
    }

    fn buildPages(self: *Self, app: *Application) void {
        const alloc = app.allocator();

        const config_obj = app.getConfig();
        defer config_obj.unref();
        const core_config = config_obj.get();

        var s = schema_mod.Schema.init(alloc, core_config) catch |err| {
            log.warn("failed to init settings schema err={}", .{err});
            return;
        };
        defer s.deinit();
        const arena = s.arena.allocator();

        // Create one page and one group per category, in enum order.
        const n_cats = @typeInfo(Category).@"enum".field_names.len;
        var pages: [n_cats]*adw.PreferencesPage = undefined;
        var groups: [n_cats]*adw.PreferencesGroup = undefined;

        inline for (std.enums.values(Category), 0..) |cat, i| {
            pages[i] = adw.PreferencesPage.new();
            pages[i].setTitle(cat.title());
            pages[i].setIconName(cat.iconName());
            groups[i] = adw.PreferencesGroup.new();
        }

        // Build one ActionRow per option and add to its group.
        for (s.options) |opt| {
            const idx = @intFromEnum(Category.of(opt.key));

            const row = adw.ActionRow.new();
            row.as(adw.PreferencesRow).setTitle(opt.key.ptr);

            const subtitle = valueSubtitle(opt, arena);
            if (subtitle.len > 0) row.setSubtitle(subtitle.ptr);

            if (opt.help.len > 0) {
                gtk.Widget.setTooltipText(row.as(gtk.Widget), opt.help.ptr);
            }

            groups[idx].add(row.as(gtk.Widget));
        }

        // Wire groups → pages → window.
        inline for (std.enums.values(Category), 0..) |_, i| {
            pages[i].add(groups[i]);
            self.as(adw.PreferencesWindow).add(pages[i]);
        }
    }

    const C = Common(Self, Private);
    pub const as = C.as;
    pub const ref = C.ref;
    pub const unref = C.unref;
    const private = C.private;

    pub const Class = extern struct {
        parent_class: Parent.Class,
        var parent: *Parent.Class = undefined;
        pub const Instance = Self;

        fn init(class: *Class) callconv(.c) void {
            gtk.Widget.Class.setTemplateFromResource(
                class.as(gtk.Widget.Class),
                comptime gresource.blueprint(.{
                    .major = 1,
                    .minor = 5,
                    .name = "settings-window",
                }),
            );
            gobject.Object.virtual_methods.dispose.implement(class, &dispose);
        }

        pub const as = C.Class.as;
        pub const bindTemplateChildPrivate = C.Class.bindTemplateChildPrivate;
        pub const bindTemplateCallback = C.Class.bindTemplateCallback;
    };
};

/// Returns a display subtitle for the option's current value(s).
/// Lifetime: tied to the arena from the schema; GTK copies on set.
fn valueSubtitle(opt: schema_mod.Option, arena: std.mem.Allocator) [:0]const u8 {
    switch (opt.kind) {
        .repeatable, .keybind => {
            if (opt.values.len == 0) return "(none)";
            // allocPrintZ doesn't exist in Zig 0.17; embed the null and slice.
            const s = std.fmt.allocPrint(arena, "{d} entries\x00", .{opt.values.len}) catch return "(many)";
            return s[0 .. s.len - 1 :0];
        },
        else => {
            if (opt.values.len > 0) return opt.values[0];
            if (opt.defaults.len > 0) return opt.defaults[0];
            return "";
        },
    }
}

/// Maps a config key to a settings page category.
const Category = enum {
    font,
    colors,
    cursor,
    window,
    shell,
    mouse,
    clipboard,
    keybindings,
    bell,
    terminal, // catch-all

    fn of(key: [:0]const u8) Category {
        const sp = std.mem.startsWith;
        const eq = std.mem.eql;
        if (sp(u8, key, "font")) return .font;
        if (sp(u8, key, "theme") or
            sp(u8, key, "background") or
            sp(u8, key, "foreground") or
            eq(u8, key, "palette") or
            sp(u8, key, "color") or
            sp(u8, key, "alpha") or
            sp(u8, key, "unfocused-")) return .colors;
        if (sp(u8, key, "cursor-")) return .cursor;
        if (sp(u8, key, "window-") or
            sp(u8, key, "gtk-") or
            sp(u8, key, "title-")) return .window;
        if (sp(u8, key, "shell-") or
            eq(u8, key, "command") or
            eq(u8, key, "working-directory")) return .shell;
        if (sp(u8, key, "mouse-")) return .mouse;
        if (sp(u8, key, "selection-") or
            sp(u8, key, "clipboard-")) return .clipboard;
        if (eq(u8, key, "keybind")) return .keybindings;
        if (sp(u8, key, "bell-")) return .bell;
        return .terminal;
    }

    fn title(self: Category) [*:0]const u8 {
        return switch (self) {
            .font => i18n._("Font"),
            .colors => i18n._("Colors & Theme"),
            .cursor => i18n._("Cursor"),
            .window => i18n._("Window"),
            .shell => i18n._("Shell"),
            .mouse => i18n._("Mouse"),
            .clipboard => i18n._("Clipboard"),
            .keybindings => i18n._("Keybindings"),
            .bell => i18n._("Bell"),
            .terminal => i18n._("Terminal"),
        };
    }

    fn iconName(self: Category) [*:0]const u8 {
        return switch (self) {
            .font => "font-x-generic-symbolic",
            .colors => "color-select-symbolic",
            .cursor => "input-mouse-symbolic",
            .window => "preferences-system-windows-symbolic",
            .shell => "utilities-terminal-symbolic",
            .mouse => "input-mouse-symbolic",
            .clipboard => "edit-paste-symbolic",
            .keybindings => "input-keyboard-symbolic",
            .bell => "audio-volume-high-symbolic",
            .terminal => "utilities-terminal-symbolic",
        };
    }
};
