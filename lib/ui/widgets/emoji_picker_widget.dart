import 'package:flutter/material.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class EmojiPickerWidget extends StatelessWidget {
  final Function(String) onEmojiSelected;
  final VoidCallback onClose;

  const EmojiPickerWidget({
    super.key,
    required this.onEmojiSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with close button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Choose an emoji',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          // Emoji picker
          Expanded(
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                onEmojiSelected(emoji.emoji);
              },
              config: Config(
                height: 256,
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  emojiSizeMax: 28,
                  backgroundColor: Colors.white,
                  recentsLimit: 28,
                  replaceEmojiOnLimitExceed: false,
                  noRecents: const Text(
                    'No Recents',
                    style: TextStyle(fontSize: 20, color: Colors.black26),
                    textAlign: TextAlign.center,
                  ),
                  loadingIndicator: const SizedBox.shrink(),
                  buttonMode: ButtonMode.MATERIAL,
                ),
                swapCategoryAndBottomBar: false,
                skinToneConfig: const SkinToneConfig(),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: Colors.grey.shade50,
                  iconColorSelected: Colors.blue,
                  backspaceColor: Colors.blue,
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: Colors.grey.shade50,
                  buttonColor: Colors.blue,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: Colors.white,
                  hintText: 'Search emoji...',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
