import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../../assets/assets.gen.dart';
import '../../../../export.dart';
import '../../../core/hook/use_mount.dart';
import '../../../core/util/chat_limit_util.dart';
import '../../../core/util/gemini.dart';
import '../../../core/util/highlight_builder.dart';
import '../../../core/widget/background.dart';
import '../../data/schema/chat_schema.dart';

part '../widget/_bottom_panel.dart';
part '../widget/_chat_item.dart';

final ai = Gemini.instance;

class HomePage extends HookWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isStarted = useState(false);
    final chats = useState(<ChatSchema>[]);
    final isGenerating = useState(false);
    final scroller = useScrollController();
    final generateViewKey = useRef(GlobalKey());
    final anim =
        useAnimationController(duration: const Duration(milliseconds: 1500));
    final scaleValue = Tween(begin: 1.0, end: 1.05)
        .animate(CurvedAnimation(parent: anim, curve: Curves.easeInOutCubic));

    useMount(() {
      anim.repeat(reverse: true);
    });

    void scrollToEnd() {
      doOnLayout(() {
        scroller.jumpTo(scroller.position.maxScrollExtent);
      });
    }

    void reset() {
      isStarted.value = false;
      chats.value = [];
      isGenerating.value = false;
      resetGemini();
    }

    void handleError() {
      final errorChat = ChatSchema(
          created: DateTime.now(),
          content: 'Unknown Error Occured',
          isFromUser: false,
          isError: true);
      chats.value = [
        ...chats.value.sublist(0, chats.value.length - 1),
        errorChat,
      ];
    }

    final subscription = useRef<StreamSubscription<dynamic>?>(null);

    void onSubmitted(String text) async {
      if (!(await trySubmitAndCheckLimit())) {
        if (context.mounted) {
          context.showErrorSnackBar(
              text: 'Your chat API usage limit has been exceeded.');
        }
        return;
      }
      if (text.isEmpty) {
        return;
      }

      isStarted.value = true;
      isGenerating.value = true;

      chats.value = [
        ...chats.value,
        ChatSchema(
          created: DateTime.now(),
          content: text,
          isFromUser: true,
        ),
        ChatSchema(
          created: DateTime.now().add(const Duration(milliseconds: 1)),
          content: '',
          isFromUser: false,
        ),
      ];
      scrollToEnd();

      subscription.value?.cancel();
      subscription.value = ai
          .streamChat(chats.value
              .whereNotIndexed((index, element) =>
                  index == chats.value.length - 1 && !element.isFromUser)
              .map(
                (e) => Content(parts: [Parts(text: e.content)], role: e.role),
              )
              .toList())
          .listen(
        (event) {
          if (event.output?.isNotEmpty == true) {
            chats.value = [
              ...chats.value.sublist(0, chats.value.length - 1),
              chats.value.last.copyWith(
                  content: chats.value.last.content + (event.output ?? '')),
            ];
          } else {
            handleError();
          }
          scrollToEnd();
        },
        onDone: () {
          isGenerating.value = false;
          scrollToEnd();
        },
        onError: (dynamic e) {
          handleError();
          isGenerating.value = false;
          log.e('Error', error: e);
        },
      );
    }

    useUnmount(() {
      subscription.value?.cancel();
    });

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: Background(),
          ),
          if (!isStarted.value)
            builldReadyPanel(scaleValue)
          else
            ListView.separated(
              itemCount: chats.value.length,
              itemBuilder: (context, index) {
                var isLastItem = index == chats.value.length - 1;

                return Column(
                  key: ValueKey(index),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ChatItem(
                      item: chats.value[index],
                      onReset: reset,
                    ),
                    if (isLastItem && isGenerating.value)
                      HookBuilder(
                        builder: (context) {
                          final anim = useAnimationController(
                              duration: const Duration(milliseconds: 1500));
                          useMount(() {
                            anim.forward();
                          });
                          return AnimatedBuilder(
                            animation: anim,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(0, 25 + (-25 * anim.value)),
                                child: Opacity(
                                  opacity: anim.value,
                                  child: child,
                                ),
                              );
                            },
                            child: Transform.translate(
                              offset: const Offset(0, 20),
                              child: Column(
                                children: [
                                  Assets.lottie.ai
                                      .lottie(width: 80, height: 80),
                                  Text(
                                    'Waiting AI Response...',
                                    style: TS.b3.c(C.sub1),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
              separatorBuilder: (context, index) => const Gap(16),
              controller: scroller,
              padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 24, bottom: 180),
            ),
          buildBottomPanel(),
          buildBottomGradient(onSubmitted, isGenerating),
        ],
      ),
    );
  }

  PosCenter builldReadyPanel(Animation<double> scaleValue) {
    return PosCenter(
      child: Pb(
        120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: scaleValue,
              builder: (context, _) {
                return Opacity(
                  opacity: scaleValue.value - 0.15,
                  child: Transform.scale(
                    scale: scaleValue.value,
                    child: Icon(MdiIcons.lightbulbOnOutline, size: 64),
                  ),
                );
              },
            ),
            const Gap(16),
            Text('Ask AI Anything', style: TS.h1.bold),
            const Gap(8),
            Text(
              '''
- How can we enjoy happy leisure time? 
- What is Google Gemini?
                    ''',
              textAlign: TextAlign.center,
              style: TS.c(C.sub1),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBottomPanel() {
    return PosBottom(
      child: IgnorePointer(
        child: Container(
          height: 150,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                C.transparent,
                Color(0xFF1b212b),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.2, 1],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildBottomGradient(void Function(String text) onSubmitted,
      ValueNotifier<bool> isGenerating) {
    return Positioned(
      bottom: 16,
      left: 24,
      right: 24,
      child: BottomPanel(
        onSubmitted: onSubmitted,
        readOnly: isGenerating.value,
      ),
    );
  }
}
