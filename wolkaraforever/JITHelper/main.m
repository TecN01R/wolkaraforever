// Entry point of the JIT helper extension.
//
// The app passes an NSXPCListenerEndpoint in the extension request's item so the helper can
// connect back to it. The extension machinery decodes request items against an allow-list
// that does not include that class, so the request would arrive empty. Before handing over to
// the system's NSExtensionMain, widen that check by this one class only; every other class is
// still validated by the original implementation. If the private method is not there, refuse
// to run rather than run without the check.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>

typedef void (*WKValidateClass)(id, SEL, Class, id, BOOL);
static WKValidateClass systemValidation;

static void WKValidateAllowingEndpoint(id decoder, SEL selector, Class class, id key, BOOL invocations) {
    if (class == NSXPCListenerEndpoint.class) return;
    systemValidation(decoder, selector, class, key, invocations);
}

__attribute__((used, visibility("default")))
int NSExtensionMain(int argc, char *argv[]) {
    Method method = class_getInstanceMethod(NSClassFromString(@"NSXPCDecoder"),
                                            NSSelectorFromString(@"_validateAllowedClass:forKey:allowingInvocations:"));
    int (*systemMain)(int, char *[]) = (int (*)(int, char *[]))dlsym(RTLD_NEXT, "NSExtensionMain");
    if (!method || !systemMain) return 70;   // EX_SOFTWARE
    systemValidation = (WKValidateClass)method_getImplementation(method);
    method_setImplementation(method, (IMP)WKValidateAllowingEndpoint);
    return systemMain(argc, argv);
}
