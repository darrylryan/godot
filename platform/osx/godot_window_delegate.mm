/*************************************************************************/
/*  godot_window_delegate.mm                                             */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2022 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2022 Godot Engine contributors (cf. AUTHORS.md).   */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "godot_window_delegate.h"

#include "display_server_osx.h"

@implementation GodotWindowDelegate

- (void)setWindowID:(DisplayServer::WindowID)wid {
	window_id = wid;
}

- (BOOL)windowShouldClose:(id)sender {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return YES;
	}

	ds->send_window_event(ds->get_window(window_id), DisplayServerOSX::WINDOW_EVENT_CLOSE_REQUEST);
	return NO;
}

- (void)windowWillClose:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);
	while (wd.transient_children.size()) {
		ds->window_set_transient(wd.transient_children.front()->get(), DisplayServerOSX::INVALID_WINDOW_ID);
	}

	if (wd.transient_parent != DisplayServerOSX::INVALID_WINDOW_ID) {
		ds->window_set_transient(window_id, DisplayServerOSX::INVALID_WINDOW_ID);
	}

	ds->window_destroy(window_id);
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);
	wd.fullscreen = true;
	// Reset window size limits.
	[wd.window_object setContentMinSize:NSMakeSize(0, 0)];
	[wd.window_object setContentMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];

	// Force window resize event.
	[self windowDidResize:notification];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);
	wd.fullscreen = false;

	// Set window size limits.
	const float scale = ds->screen_get_max_scale();
	if (wd.min_size != Size2i()) {
		Size2i size = wd.min_size / scale;
		[wd.window_object setContentMinSize:NSMakeSize(size.x, size.y)];
	}
	if (wd.max_size != Size2i()) {
		Size2i size = wd.max_size / scale;
		[wd.window_object setContentMaxSize:NSMakeSize(size.x, size.y)];
	}

	// Restore resizability state.
	if (wd.resize_disabled) {
		[wd.window_object setStyleMask:[wd.window_object styleMask] & ~NSWindowStyleMaskResizable];
	}

	// Restore on-top state.
	if (wd.on_top) {
		[wd.window_object setLevel:NSFloatingWindowLevel];
	}

	// Force window resize event.
	[self windowDidResize:notification];
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);

	CGFloat new_scale_factor = [wd.window_object backingScaleFactor];
	CGFloat old_scale_factor = [[[notification userInfo] objectForKey:@"NSBackingPropertyOldScaleFactorKey"] doubleValue];

	if (new_scale_factor != old_scale_factor) {
		// Set new display scale and window size.
		const float scale = ds->screen_get_max_scale();
		const NSRect content_rect = [wd.window_view frame];

		wd.size.width = content_rect.size.width * scale;
		wd.size.height = content_rect.size.height * scale;

		ds->send_window_event(wd, DisplayServerOSX::WINDOW_EVENT_DPI_CHANGE);

		CALayer *layer = [wd.window_view layer];
		if (layer) {
			layer.contentsScale = scale;
		}

		//Force window resize event
		[self windowDidResize:notification];
	}
}

- (void)windowDidResize:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);
	const NSRect content_rect = [wd.window_view frame];
	const float scale = ds->screen_get_max_scale();
	wd.size.width = content_rect.size.width * scale;
	wd.size.height = content_rect.size.height * scale;

	CALayer *layer = [wd.window_view layer];
	if (layer) {
		layer.contentsScale = scale;
	}

	ds->window_resize(window_id, wd.size.width, wd.size.height);

	if (!wd.rect_changed_callback.is_null()) {
		Variant size = Rect2i(ds->window_get_position(window_id), ds->window_get_size(window_id));
		Variant *sizep = &size;
		Variant ret;
		Callable::CallError ce;
		wd.rect_changed_callback.call((const Variant **)&sizep, 1, ret, ce);
	}
}

- (void)windowDidMove:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);
	ds->release_pressed_events();

	if (!wd.rect_changed_callback.is_null()) {
		Variant size = Rect2i(ds->window_get_position(window_id), ds->window_get_size(window_id));
		Variant *sizep = &size;
		Variant ret;
		Callable::CallError ce;
		wd.rect_changed_callback.call((const Variant **)&sizep, 1, ret, ce);
	}
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);

	if (ds->mouse_get_mode() == DisplayServer::MOUSE_MODE_CAPTURED) {
		const NSRect content_rect = [wd.window_view frame];
		NSRect point_in_window_rect = NSMakeRect(content_rect.size.width / 2, content_rect.size.height / 2, 0, 0);
		NSPoint point_on_screen = [[wd.window_view window] convertRectToScreen:point_in_window_rect].origin;
		CGPoint mouse_warp_pos = { point_on_screen.x, CGDisplayBounds(CGMainDisplayID()).size.height - point_on_screen.y };
		CGWarpMouseCursorPosition(mouse_warp_pos);
	} else {
		ds->update_mouse_pos(wd, [wd.window_object mouseLocationOutsideOfEventStream]);
	}

	ds->set_last_focused_window(window_id);
	ds->send_window_event(wd, DisplayServerOSX::WINDOW_EVENT_FOCUS_IN);
}

- (void)windowDidResignKey:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);

	ds->release_pressed_events();
	ds->send_window_event(wd, DisplayServerOSX::WINDOW_EVENT_FOCUS_OUT);
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);

	ds->release_pressed_events();
	ds->send_window_event(wd, DisplayServerOSX::WINDOW_EVENT_FOCUS_OUT);
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
	DisplayServerOSX *ds = (DisplayServerOSX *)DisplayServer::get_singleton();
	if (!ds || !ds->has_window(window_id)) {
		return;
	}

	DisplayServerOSX::WindowData &wd = ds->get_window(window_id);

	ds->set_last_focused_window(window_id);
	ds->send_window_event(wd, DisplayServerOSX::WINDOW_EVENT_FOCUS_IN);
}

@end
