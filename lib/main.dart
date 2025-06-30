import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart'; // для мобилки
import 'dart:html' as html;
import 'package:file_picker/file_picker.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:async';

class AudioRecorderScreen extends StatefulWidget {
  @override
  _AudioRecorderScreenState createState() => _AudioRecorderScreenState();
}

class _AudioRecorderScreenState extends State<AudioRecorderScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  SpeechToText _speechToText = SpeechToText();
  final TextEditingController textToSpeechController = TextEditingController();

  String? _audioPath;
  String _lastWords = '';
  String _savedWords = '';
  List<String> _chunks = [];

  // переменные управления записью и распознаванием речи
  bool _isRecording = false;
  bool _speechEnabled = false;
  bool _isEditing = false;
  bool _switchRecorder = true;
  // переменные управления чанками:
  
  Timer? _chunkTimer;
  final int chunkDuration = 30; // секунд

  @override
  void initState() {
    //сам пакет надо однократно инициализировать при запуске страницы
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onStatus: _onSpeechStatus,
    );
    setState(() {});
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    //сохраняет результат распознавания и добавляет к чанку буфер новых (последних) слов
    setState(() {
      _lastWords = result.recognizedWords;
      textToSpeechController.text =
          _chunks.join(' ') + (_lastWords.isNotEmpty ? ' ' + _lastWords : '');
    });
  }

  void _onSpeechStatus(String status) {
    // если распознавание неожиданно остановилось — перезапустить, если нужно
    // тк есть платформенные ограничения, web автоматически останавливает голосовой ввод
    if (status == 'done' && _isRecording && !_isEditing) {
      Future.delayed(Duration(milliseconds: 300), () {
        if (!_speechToText.isListening && _isRecording && !_isEditing) {
          _speechToText.listen(onResult: _onSpeechResult);
        }
      });
    }
  }

  void _toggleEditing() async {
    setState(() {
      _isEditing = !_isEditing;
    });

    if (_isEditing) {
      // Вход в режим редактирования
      if (_speechToText.isListening) {
        await _speechToText.stop();
      }
      _lastWords = ''; // Сбросить только временный буфер, но не трогать _chunks и _savedWords!
      //если не сделать, последный чанк начинает дублировать и перезаписывать
    } else {
      // Выход из режима редактирования
      // Обновить список чанков из текстового поля (если нужно)
      final editedText = textToSpeechController.text.trim();
      _chunks = editedText.isNotEmpty ? editedText.split(RegExp(r'\s+')) : [];
      _lastWords = '';
      if (_isRecording && _speechEnabled && !_speechToText.isListening) {
        await _speechToText.listen(onResult: _onSpeechResult);
      }
    }
  }

  void _startChunking() {
    //контролирует период записи чанков
    _chunkTimer?.cancel();
    _chunkTimer =
        Timer.periodic(Duration(seconds: chunkDuration), (timer) async {
      if (_speechToText.isListening && !_isEditing) {
        await _speechToText.stop();
        _saveCurrentChunk();
        await Future.delayed(Duration(milliseconds: 300));
        if (_isRecording && !_isEditing) {
          await _speechToText.listen(onResult: _onSpeechResult);
        }
      }
    });
  }

  void _stopChunking() {
    _chunkTimer?.cancel();
    _chunkTimer = null;
    String allRecognizedText = _chunks.join(' ');
    print(allRecognizedText);
  }

  void _saveCurrentChunk() {
    if (_lastWords.trim().isNotEmpty) {
      _chunks.add(_lastWords.trim());
      _lastWords = '';
    }
    textToSpeechController.text = _chunks.join(' ');
  }

  Future<void> _startRecording() async {
    //запись аудио в файл
    if (_switchRecorder) {
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: 'audio_recording.wav',
      );
    }

    if (_speechEnabled && !_isEditing) {
      await _speechToText.listen(onResult: _onSpeechResult);
      _startChunking();
    }

    setState(() {
      _isRecording = true;
      _savedWords = textToSpeechController.text;
      _lastWords = '';
      _chunks = _savedWords.trim().isNotEmpty ? [_savedWords.trim()] : [];
    });
  }

  Future<void> _stopRecording() async {
    //остановка записи аудио и сохранение локально
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

    // Сохраняем последний чанк после остановки распознавания!
    _saveCurrentChunk();

    _stopChunking();

    setState(() {
      _isRecording = false;
    });
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _chunkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: 10),
              if (_switchRecorder && _isRecording)
                Text('Записываем аудио...')
              else if (_isEditing)
                Text('Распознавание речи отключено'),
              Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: Theme.of(context).colorScheme.primary),
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
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                  fontSize: 12),
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
                          onPressed:
                              _isRecording ? _stopRecording : _startRecording,
                          icon: _isRecording
                              ? Icons.stop_circle
                              : Icons.play_circle,
                          tooltipMessage: _isRecording
                              ? 'Завершить прослушивание'
                              : 'Подключиться к микрофону',
                          iconSize: 40,
                        ),
                        SizedBox(width: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
            onSurface: Color(0xFF427FF0))),
    home: AudioRecorderScreen()));
