import 'package:web/web.dart' as web;

// Web implementation - checks if running on iOS Safari
bool isIOSSafari() {
  try {
    final userAgent = web.window.navigator.userAgent.toLowerCase();
    
    // Check for iOS devices (iPhone, iPad, iPod)
    final isIOS = userAgent.contains('iphone') || 
                  userAgent.contains('ipad') || 
                  userAgent.contains('ipod');
    
    // Also check for iOS 13+ iPad which reports as Mac
    final isIPadOS = userAgent.contains('macintosh') && 
                     web.window.navigator.maxTouchPoints > 0;
    
    return isIOS || isIPadOS;
  } catch (e) {
    return false;
  }
}
