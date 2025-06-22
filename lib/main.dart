import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart'; // для мобилки
import 'dart:html' as html;
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class AudioRecorderScreen extends StatefulWidget {
  @override
  _AudioRecorderScreenState createState() => _AudioRecorderScreenState();
}

class _AudioRecorderScreenState extends State<AudioRecorderScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  SpeechToText _speechToText = SpeechToText();
  final TextEditingController textToSpeechController = TextEditingController();

  String? _audioPath;
  // дробим текст на части, так как пакет в реальном времени редактирует предыдущие слова, и при попытке вручную редактировать текст не будет сохранять отредактированное\\будет сохранять все версии текста
  String _lastWords = '';
  String _savedWords = '';

  bool _isRecording = false;
  bool _speechEnabled = false;
  bool _isEditing = false;
  bool _switchRecorder = true;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  /// This has to happen only once per app --docs
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      // Объединяем сохранённый текст с новыми распознанными словами
      textToSpeechController.text =
          _savedWords + (_savedWords.isNotEmpty ? ' ' : '') + _lastWords;
    });
  }
//TODO починить баг: не сохраняется предзаписанное аудио, если переключиться на редактирование, но ничего не редактировать и сразу вернуться к распознаванию (после того, как будем сохранять чанками)
  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;

      if (_isEditing) {
        // Вход в режим редактирования
        // _savedWords = textToSpeechController.text;
        _lastWords = '';
        if (_speechToText.isListening) {
          _speechToText.stop();
        }
      } else {
        // Выход из режима редактирования
        if (_isRecording && _speechEnabled && !_speechToText.isListening) {
          _speechToText.listen(onResult: _onSpeechResult);
        }
      }
    });
  }
  //TODO починить САААМУЮ большую проблему: писать чанками (каждые N секунд), потому что ловит RangeError: Invalid array length на длительном аудио
  Future<void> _startRecording() async {
    //запуск доступа к микро для мобилки, для веб это не нужно

    // final microphoneStatus = await Permission.microphone.status;
    // final storageStatus = await Permission.storage.status;

    // if (!microphoneStatus.isGranted) {
    //   await Permission.microphone.request();
    // }
    // if (!storageStatus.isGranted) {
    //   await Permission.storage.request();
    // }

    // // Если разрешения предоставлены, начинаем запись
    // if (await Permission.microphone.isGranted && await Permission.storage.isGranted) {
    //TODO выкидывать сообщение об ошибке если не нашел микрофон

    if (_switchRecorder) {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: 'audio_recording.wav',
      );
    }
    ;

    if (_speechEnabled && !_isEditing) {
      await _speechToText.listen(onResult: _onSpeechResult);
    }

    setState(() {
      _isRecording = true;
      _savedWords = textToSpeechController.text;
      _lastWords = '';
    });
  }
//TODO тоже сделать сохранение чанками, потому что накопится буфер и всё упадет, подобрать формат сохранения
  Future<void> _stopRecording() async {
    if (_switchRecorder) {
      final audioPath = await _audioRecorder.stop();
      _audioPath = audioPath;

      final anchor = html.AnchorElement(href: audioPath)
        ..target = 'blank'
        ..download = 'audio_recording.wav';
      anchor.click();
    }

    if (_speechToText.isListening) {
      await _speechToText.stop();
    }

    setState(() {
      _isRecording = false;
    });
  }

  //TODO написать распознавание загруженных файлов
  // Future<void> _downloadFile() async {
  //   FilePickerResult? result = await FilePicker.platform.pickFiles();
  //   if (result != null) {
  //     File file = File(result.files.single.path!);
  //
  //     print('я пока ничего не умею делать с файлом');
  //   } else {
  //     // User canceled the picker
  //   }
  // }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 10),
            if (_switchRecorder && _isRecording)
              Text('Записываем аудио...')
            // else if (_switchRecorder && _audioPath != null)
            //   Text('Запись разговора скачана!'),
            else if (_isEditing) Text('Распознавание речи отключено'),

            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.primary),
                borderRadius: BorderRadius.circular(10),
              ),
              margin: EdgeInsets.all(20),
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Expanded(
                      child: SwitchListTile(
                          title: Text('Сохранять аудиозапись'),
                          subtitle: Text(
                            _switchRecorder
                                ? 'Сохранение включено'
                                : 'Сохранение отключено',
                            style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 12),
                          ),
                          value: _switchRecorder,
                          onChanged: (bool value) {
                            setState(() {
                              _switchRecorder = value;
                            });
                          }),
                    )
                  ]),
                  SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: InputField(
                      controller: textToSpeechController,
                      isEditing: _isEditing,
                      suffixIcon: CustomIconButton(
                        onPressed: _toggleEditing,
                        icon: _isEditing ? Icons.hearing : Icons.edit,
                        tooltipMessage: _isEditing
                            ? 'Распознавать речь'
                            : 'Редактировать текст',
                      ),
                      onChanged: (text) {
                        if (_isEditing) {
                          _savedWords = text;
                        }
                      },
                    ),
                  ),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomIconButton(
                        onPressed: _isRecording ? _stopRecording : _startRecording,
                        icon: _isRecording ? Icons.stop_circle : Icons.play_circle,
                        tooltipMessage: _isRecording
                            ? 'Завершить прослушивание'
                            : 'Подключиться к микрофону',
                        iconSize : 40,
                      ),
                                            SizedBox(width: 20),
                    ],
                  ),
                ],
              ),
            ),

            // Row(
            //   mainAxisSize: MainAxisSize.min,
            //   children: [
            //     ElevatedButton(
            //       onPressed: () {
            //         _downloadFile();
            //       },
            //       child: Text('Download audio'),
            //     ),
            //     SizedBox(height: 20),
            //   ],
            // ),
          ],
        ),
      ),
    );
  }
}

class InputField extends StatelessWidget {
  final TextEditingController controller;
  final bool isEditing;
  final Function(String)? onChanged;
  final Widget? suffixIcon;

  InputField({
    super.key,
    required this.controller,
    required this.isEditing,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
          filled: true,
          fillColor: isEditing
              ? Color(0x5BC2C8D6)
              : Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          suffixIcon: Padding(
            padding: const EdgeInsets.all(24.0),
            child: suffixIcon,
          )),
      maxLines: null,
      keyboardType: TextInputType.multiline,
      readOnly: !isEditing,
      onChanged: onChanged,
    );
  }
}

class CustomIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String? tooltipMessage;
  final double? iconSize;

  const CustomIconButton({
    Key? key,
    required this.onPressed,
    required this.icon,
    this.tooltipMessage,
    this.iconSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltipMessage,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Theme.of(context).colorScheme.onSecondary,
          size: iconSize,
        ),
      ),
    );
  }
}

void main() => runApp(MaterialApp(
    theme: ThemeData(
        colorScheme: const ColorScheme(
            brightness: Brightness.light,
            primary: Color(0xFFC2C8D6),
            onPrimary: Color(0xFF657699),
            secondary: Color(0xFFC2C8D6),
            onSecondary: Color(0xFF427FF0),
            error: Color(0xFFFFFFFF),
            onError: Colors.red,
            surface: Color(0xFFFFFFFF),
            onSurface: Color(0xFF427FF0))
        // textTheme: TextTheme(
        // bodyLarge: ,
        // headlineLarge:

        ),
    home: AudioRecorderScreen()));
