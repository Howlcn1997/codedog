// WindowServer SPI is resolved at runtime so unsupported systems can fall back safely.
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <node_api.h>
#include <cmath>
#include <cstring>
#include <dlfcn.h>
#include <vector>
#include <algorithm>

static napi_value SetBlurRadius(napi_env env, napi_callback_info info) {
  void *refreshOnly = nullptr;
  size_t argc = 3;
  napi_value argv[3];
  napi_get_cb_info(env, info, &argc, argv, nullptr, &refreshOnly);
  bool isBuffer = false;
  if (argc < 1 || napi_is_buffer(env, argv[0], &isBuffer) != napi_ok || !isBuffer) {
    napi_throw_type_error(env, nullptr, "Expected a native window handle"); return nullptr;
  }
  void *buffer = nullptr; size_t length = 0;
  napi_get_buffer_info(env, argv[0], &buffer, &length);
  if (length != sizeof(void *) || ![NSThread isMainThread]) {
    napi_throw_error(env, nullptr, "Invalid handle or non-main thread"); return nullptr;
  }
  double radius = 0;
  if ((argc != 2 && argc != 3) || (napi_get_value_double(env, argv[1], &radius) != napi_ok ||
      !std::isfinite(radius) || std::floor(radius) != radius || radius < 0 || radius > 80)) {
    napi_throw_range_error(env, nullptr, "Blur radius must be between 0 and 80"); return nullptr;
  }
  bool compact = radius > 0;
  if (argc == 3 && napi_get_value_bool(env, argv[2], &compact) != napi_ok) {
    napi_throw_type_error(env, nullptr, "Compact mode must be a boolean"); return nullptr;
  }
  void *handle = nullptr;
  std::memcpy(&handle, buffer, sizeof(handle));
  NSView *content = nil;
  // Match known live windows instead of dereferencing an arbitrary address.
  for (NSWindow *window in NSApp.windows) {
    if ((__bridge void *)window.contentView == handle) { content = window.contentView; break; }
  }
  if (!content) { napi_throw_error(env, nullptr, "Native window is not live"); return nullptr; }
  using Connection = int (*)();
  using SetBlur = int (*)(int, int, int);
  static auto connection = reinterpret_cast<Connection>(dlsym(RTLD_DEFAULT, "CGSMainConnectionID"));
  static auto setBlur = reinterpret_cast<SetBlur>(dlsym(RTLD_DEFAULT, "CGSSetWindowBackgroundBlurRadius"));
  if (!connection || !setBlur) {
    napi_throw_error(env, nullptr, "当前 macOS 不支持自定义窗口模糊半径"); return nullptr;
  }
  // Focus changes must restore blur immediately without rebuilding the frame,
  // server shape or shadow. Those operations are only needed for geometry changes.
  if (refreshOnly) {
    const int status = setBlur(connection(), static_cast<int>(content.window.windowNumber), static_cast<int>(radius));
    if (status != 0) { napi_throw_error(env, nullptr, "macOS 无法恢复窗口模糊"); return nullptr; }
    napi_value result; napi_create_int32(env, status, &result); return result;
  }
  // WindowServer blur can use the rectangular window bounds independently of
  // AppKit's rounded content mask. Clip the server-side shape as well.
  using NewRegion = int (*)(const CGRect *, int, CFTypeRef *);
  using SetClip = int (*)(int, int, CFTypeRef);
  // This SPI uses 32-bit float coordinates even in a 64-bit process.
  using SetShape = int (*)(int, int, float, float, CFTypeRef);
  using ReleaseRegion = int (*)(CFTypeRef);
  static auto newRegion = reinterpret_cast<NewRegion>(dlsym(RTLD_DEFAULT, "CGSNewRegionWithRectList"));
  static auto setClip = reinterpret_cast<SetClip>(dlsym(RTLD_DEFAULT, "CGSSetWindowClipShape"));
  static auto setShape = reinterpret_cast<SetShape>(dlsym(RTLD_DEFAULT, "CGSSetWindowShape"));
  static auto releaseRegion = reinterpret_cast<ReleaseRegion>(dlsym(RTLD_DEFAULT, "CGSReleaseRegion"));
  if (!newRegion || !setShape || !setClip || !releaseRegion) {
    napi_throw_error(env, nullptr, "当前 macOS 不支持窗口模糊圆角裁切"); return nullptr;
  }
  NSWindow *window = content.window;
  // Compact mode has exactly one silhouette. A titled AppKit frame adds its
  // own continuous corner and rim, which cannot align with a circular CGS mask.
  // Keep the original style per window and restore it for standard mode.
  static char originalStyleKey;
  NSNumber *originalStyle = objc_getAssociatedObject(window, &originalStyleKey);
  NSRect frame = window.frame;
  if (compact && !originalStyle) {
    objc_setAssociatedObject(window, &originalStyleKey, @(window.styleMask), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.styleMask = window.styleMask & ~(NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView);
    [window setFrame:frame display:YES];
  } else if (!compact && originalStyle) {
    objc_setAssociatedObject(window, &originalStyleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.styleMask = originalStyle.unsignedIntegerValue;
    [window setFrame:frame display:YES];
  }
  const CGFloat width = NSWidth(window.frame), height = NSHeight(window.frame);
  const CGFloat corner = compact ? std::min(CGFloat(16), std::min(width, height) / 2) : 0;
  // Layer-backed content is composited separately from the WindowServer clip.
  // Use the same circular silhouette for the content and the server shape.
  NSView *frameView = window.contentView.superview;
  static char savedLayerKey;
  if (compact) {
    frameView.wantsLayer = YES;
    CALayer *layer = frameView.layer;
    if (!objc_getAssociatedObject(layer, &savedLayerKey))
      objc_setAssociatedObject(layer, &savedLayerKey,
        @[@(layer.cornerRadius), @(layer.masksToBounds), layer.cornerCurve ?: kCACornerCurveCircular],
        OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    layer.cornerRadius = corner;
    layer.cornerCurve = kCACornerCurveCircular;
    layer.masksToBounds = YES;
  } else {
    CALayer *layer = frameView.layer;
    NSArray *saved = objc_getAssociatedObject(layer, &savedLayerKey);
    if (saved) {
      layer.cornerRadius = [saved[0] doubleValue];
      layer.masksToBounds = [saved[1] boolValue];
      layer.cornerCurve = saved[2];
      objc_setAssociatedObject(layer, &savedLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
  }
  std::vector<CGRect> strips;
  if (corner > 0) {
    const CGFloat step = 1 / std::max(window.backingScaleFactor, CGFloat(1));
    for (CGFloat y = 0; y < corner; y += step) {
      const CGFloat h = std::min(step, corner - y);
      const CGFloat dy = corner - (y + h / 2);
      const CGFloat inset = corner - std::sqrt(std::max(CGFloat(0), corner * corner - dy * dy));
      strips.push_back(CGRectMake(inset, y, width - inset * 2, h));
      strips.push_back(CGRectMake(inset, height - y - h, width - inset * 2, h));
    }
    strips.push_back(CGRectMake(0, corner, width, height - corner * 2));
  } else {
    strips.push_back(CGRectMake(0, 0, width, height));
  }
  CFTypeRef region = nullptr;
  if (newRegion(strips.data(), static_cast<int>(strips.size()), &region) != 0 || !region) {
    napi_throw_error(env, nullptr, "无法创建窗口圆角区域"); return nullptr;
  }
  const int status = setBlur(connection(), static_cast<int>(content.window.windowNumber), static_cast<int>(radius));
  if (status != 0) {
    releaseRegion(region);
    napi_throw_error(env, nullptr, "macOS 无法应用窗口模糊半径"); return nullptr;
  }
  // CGSSetWindowShape takes the window's SCREEN origin, not a local offset.
  // Passing (0, 0) moves its server surface while AppKit still caches the old frame.
  const CGFloat screenTop = NSMaxY(NSScreen.screens.firstObject.frame);
  const CGPoint origin = CGPointMake(NSMinX(window.frame), screenTop - NSMaxY(window.frame));
  const int shapeStatus = setShape(connection(), static_cast<int>(window.windowNumber), origin.x, origin.y, region);
  const int clipStatus = setClip(connection(), static_cast<int>(window.windowNumber), region);
  releaseRegion(region);
  if (shapeStatus != 0 || clipStatus != 0) {
    napi_throw_error(env, nullptr, "无法应用窗口圆角区域"); return nullptr;
  }
  [window invalidateShadow];
  napi_value result;
  napi_create_int32(env, status, &result);
  return result;
}

// Read the actual WindowServer clip for integration checks, not a cached radius.
static napi_value InspectClip(napi_env env, napi_callback_info info) {
  size_t argc = 1; napi_value arg; bool isBuffer = false; void *inspection = nullptr;
  napi_get_cb_info(env, info, &argc, &arg, nullptr, &inspection);
  if (argc != 1 || napi_is_buffer(env, arg, &isBuffer) != napi_ok || !isBuffer) {
    napi_throw_type_error(env, nullptr, "Expected a native window handle"); return nullptr;
  }
  void *buffer = nullptr, *handle = nullptr; size_t length = 0;
  napi_get_buffer_info(env, arg, &buffer, &length);
  if (length != sizeof(void *) || ![NSThread isMainThread]) {
    napi_throw_error(env, nullptr, "Invalid window handle"); return nullptr;
  }
  std::memcpy(&handle, buffer, sizeof(handle));
  NSWindow *window = nil;
  for (NSWindow *candidate in NSApp.windows)
    if ((__bridge void *)candidate.contentView == handle) { window = candidate; break; }
  using Connection = int (*)();
  if (inspection) {
    using GetScreenRect = int (*)(int, int, CGRect *);
    auto connection = reinterpret_cast<Connection>(dlsym(RTLD_DEFAULT, "CGSMainConnectionID"));
    auto getRect = reinterpret_cast<GetScreenRect>(dlsym(RTLD_DEFAULT, "CGSGetScreenRectForWindow"));
    CGRect rect;
    if (!window || !connection || !getRect || getRect(connection(), static_cast<int>(window.windowNumber), &rect) != 0) {
      napi_throw_error(env, nullptr, "Cannot read window screen bounds"); return nullptr;
    }
    napi_value result; napi_create_object(env, &result);
    const char *keys[] = {"x", "y", "width", "height"};
    double values[] = {rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
    for (int i=0; i<4; ++i) { napi_value value; napi_create_double(env, values[i], &value); napi_set_named_property(env, result, keys[i], value); }
    return result;
  }
  using CopyClip = int (*)(int, int, CFTypeRef *);
  using Contains = bool (*)(CFTypeRef, const CGPoint *);
  using Release = int (*)(CFTypeRef);
  auto connection = reinterpret_cast<Connection>(dlsym(RTLD_DEFAULT, "CGSMainConnectionID"));
  auto copy = reinterpret_cast<CopyClip>(dlsym(RTLD_DEFAULT, "CGSCopyWindowClipShape"));
  auto contains = reinterpret_cast<Contains>(dlsym(RTLD_DEFAULT, "CGSPointInRegion"));
  auto release = reinterpret_cast<Release>(dlsym(RTLD_DEFAULT, "CGSReleaseRegion"));
  CFTypeRef region = nullptr;
  if (!window || !connection || !copy || !contains || !release ||
      copy(connection(), static_cast<int>(window.windowNumber), &region) != 0 || !region) {
    napi_throw_error(env, nullptr, "Cannot read window clip"); return nullptr;
  }
  CGFloat w = NSWidth(window.frame), h = NSHeight(window.frame);
  CGPoint points[] = {{1,1},{w-2,1},{1,h-2},{w-2,h-2},{w/2,h/2}};
  napi_value result; napi_create_array_with_length(env, 5, &result);
  for (uint32_t i=0; i<5; ++i) {
    napi_value value; napi_get_boolean(env, contains(region, &points[i]), &value);
    napi_set_element(env, result, i, value);
  }
  release(region);
  return result;
}

static napi_value Init(napi_env env, napi_value exports) {
  napi_value function;
  napi_create_function(env, "setBlurRadius", NAPI_AUTO_LENGTH, SetBlurRadius, nullptr, &function);
  napi_set_named_property(env, exports, "setBlurRadius", function);
  napi_create_function(env, "inspectClip", NAPI_AUTO_LENGTH, InspectClip, nullptr, &function);
  napi_set_named_property(env, exports, "inspectClip", function);
  static int refreshOnly;
  napi_create_function(env, "refreshBlur", NAPI_AUTO_LENGTH, SetBlurRadius, &refreshOnly, &function);
  napi_set_named_property(env, exports, "refreshBlur", function);
  static int boundsInspection;
  napi_create_function(env, "inspectBounds", NAPI_AUTO_LENGTH, InspectClip, &boundsInspection, &function);
  napi_set_named_property(env, exports, "inspectBounds", function);
  return exports;
}
NAPI_MODULE(NODE_GYP_MODULE_NAME, Init)
