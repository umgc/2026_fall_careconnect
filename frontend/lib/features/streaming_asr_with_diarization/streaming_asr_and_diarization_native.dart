import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as Path;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
//import 'package:new_simple_audio_trimmer/simple_audio_trimmer.dart';
import '../../services/notetaker_config_service.dart';
import '../notetaker/models/patient_note_model.dart';
import './utils.dart';

// Remember to change `assets` in ../pubspec.yaml
// and download files to ../assets
Future<sherpa_onnx.OnlineModelConfig> getOnlineModelConfig() async {
  final modelDir = 'assets/sherpa-onnx-streaming-zipformer-en-2023-06-26';
  return sherpa_onnx.OnlineModelConfig(
    transducer: sherpa_onnx.OnlineTransducerModelConfig(
      encoder: await copyAssetFile(
        '$modelDir/encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
      ),
      decoder: await copyAssetFile(
        '$modelDir/decoder-epoch-99-avg-1-chunk-16-left-128.onnx',
      ),
      joiner: await copyAssetFile(
        '$modelDir/joiner-epoch-99-avg-1-chunk-16-left-128.onnx',
      ),
    ),
    tokens: await copyAssetFile('$modelDir/tokens.txt'),
    modelType: 'zipformer2',
  );
}

Future<sherpa_onnx.OfflineModelConfig> getOfflineModelConfig() async {
  final modelDir = 'assets/sherpa-onnx-zipformer-gigaspeech-2023-12-12';
  return sherpa_onnx.OfflineModelConfig(
    transducer: sherpa_onnx.OfflineTransducerModelConfig(
      encoder: await copyAssetFile(
        '$modelDir/encoder-epoch-30-avg-1.int8.onnx',
      ),
      decoder: await copyAssetFile('$modelDir/decoder-epoch-30-avg-1.onnx'),
      joiner: await copyAssetFile('$modelDir/joiner-epoch-30-avg-1.int8.onnx'),
    ),
    tokens: await copyAssetFile('$modelDir/tokens.txt'),
    numThreads: 1,
  );
}

Float32List computeEmbedding({
  required sherpa_onnx.SpeakerEmbeddingExtractor extractor,
  required String filename,
}) {
  final waveData = sherpa_onnx.readWave(filename);
  final stream = extractor.createStream();

  stream.acceptWaveform(
    samples: waveData.samples,
    sampleRate: waveData.sampleRate,
  );
  stream.inputFinished();
  final embedding = extractor.compute(stream);
  stream.free();
  return embedding;
}

Future<sherpa_onnx.OnlineRecognizer> createOnlineRecognizer() async {
  final modelConfig = await getOnlineModelConfig();
  final config = sherpa_onnx.OnlineRecognizerConfig(
    model: modelConfig,
    ruleFsts: '',
  );
  return sherpa_onnx.OnlineRecognizer(config);
}

Future<sherpa_onnx.OfflineRecognizer> createOfflineRecognizer() async {
  final modelConfig = await getOfflineModelConfig();
  final config = sherpa_onnx.OfflineRecognizerConfig(model: modelConfig);
  return sherpa_onnx.OfflineRecognizer(config);
}

class StreamingAsrAndDiarizationScreen extends StatefulWidget {
  final Function(PatientNote)? onUploadSuccess;
  final Function(String)? onUploadError;
  final String? patientId;
  const StreamingAsrAndDiarizationScreen({
    super.key,
    this.onUploadSuccess,
    this.onUploadError,
    this.patientId,
  });

  @override
  State<StreamingAsrAndDiarizationScreen> createState() =>
      _StreamingAsrAndDiarizationScreenState();
}

class _StreamingAsrAndDiarizationScreenState
    extends State<StreamingAsrAndDiarizationScreen> {
  late final TextEditingController _controller;
  final ScrollController _scrollController = ScrollController();
  late final AudioRecorder _audioRecorder;
  List<int> recordedData = [];
  String _textToDisplay = '';
  String _last = '';
  bool _isInitialized = false;
  bool _isLoading = false;
  List<String> _speakerList = [];
  String? _selectedSpeaker;
  late final TextEditingController _newSpeakerName;
  bool _noteSaved = false;
  PatientNote? _savedNote;

  sherpa_onnx.OnlineRecognizer? _recognizer;
  sherpa_onnx.OfflineRecognizer? _offlineRecognizer;
  sherpa_onnx.OnlineStream? _stream;
  final int _sampleRate = 16000;

  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();
    _controller = TextEditingController();
    _newSpeakerName = TextEditingController();
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    _noteSaved = false;
    _savedNote = null;
    _textToDisplay = '';
    _speakerList = [];
    _selectedSpeaker = null;
    super.initState();
  }

  Future<void> _start() async {
    setState(() {
      _controller.clear();
      _newSpeakerName.clear();
      _last = '';
      recordedData = [];
      _textToDisplay = '';
      _speakerList = [];
      _selectedSpeaker = null;
    });
    if (!_isInitialized) {
      sherpa_onnx.initBindings();
      setState(() {
        _isLoading = true;
      });
      _recognizer = await createOnlineRecognizer();
      setState(() {
        _isLoading = false;
      });
      _stream = _recognizer?.createStream();
      _isInitialized = true;
    }

    try {
      if (await _audioRecorder.hasPermission()) {
        const encoder = AudioEncoder.pcm16bits;

        if (!await _isEncoderSupported(encoder)) {
          return;
        }

        final devs = await _audioRecorder.listInputDevices();
        debugPrint(devs.toString());

        const config = RecordConfig(
          encoder: encoder,
          sampleRate: 16000,
          numChannels: 1,
        );

        final stream = await _audioRecorder.startStream(config);
        stream.listen(
          (data) {
            recordedData.addAll(data);
            final samplesFloat32 = convertBytesToFloat32(
              Uint8List.fromList(data),
            );
            _stream!.acceptWaveform(
              samples: samplesFloat32,
              sampleRate: _sampleRate,
            );
            while (_recognizer!.isReady(_stream!)) {
              _recognizer!.decode(_stream!);
            }
            final result = _recognizer!.getResult(_stream!);
            final text = result.text;
            String textToDisplay = _last;
            if (text != '') {
              if (_last == '') {
                textToDisplay = text;
              } else {
                textToDisplay = '$_last\n$text';
              }
            }

            if (_recognizer!.isEndpoint(_stream!)) {
              _recognizer!.reset(_stream!);
              if (text != '') {
                _last = textToDisplay;
              }
            }
            _controller.value = TextEditingValue(
              text: textToDisplay,
              selection: TextSelection.collapsed(offset: textToDisplay.length),
            );
            _scrollController
                .jumpTo(_scrollController.position.maxScrollExtent);
          },
          onDone: () {
            print('stream stopped.');
          },
        );
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> _stop() async {
    _stream!.free();
    _stream = _recognizer!.createStream();

    await _audioRecorder.stop();
    setState(() {
      _isLoading = true;
    });
    if (_controller.value.text.isNotEmpty) {
      saveTemporaryFile(recordedData, _sampleRate);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> saveTemporaryFile(List<int> data, int sampleRate) async {
    Directory? directory = await getExternalStorageDirectory();
    String filename = "";
    if (directory != null) {
      filename = "${directory.path}/temporary.wav";
      File recordedFile = File(filename);

      var channels = 1;

      int byteRate = ((16 * sampleRate * channels) / 8).round();

      var size = data.length;

      var fileSize = size + 36;

      Uint8List header = Uint8List.fromList([
        // "RIFF"
        82, 73, 70, 70,
        fileSize & 0xff,
        (fileSize >> 8) & 0xff,
        (fileSize >> 16) & 0xff,
        (fileSize >> 24) & 0xff,
        // WAVE
        87, 65, 86, 69,
        // fmt
        102, 109, 116, 32,
        // fmt chunk size 16
        16, 0, 0, 0,
        // Type of format
        1, 0,
        // One channel
        channels, 0,
        // Sample rate
        sampleRate & 0xff,
        (sampleRate >> 8) & 0xff,
        (sampleRate >> 16) & 0xff,
        (sampleRate >> 24) & 0xff,
        // Byte rate
        byteRate & 0xff,
        (byteRate >> 8) & 0xff,
        (byteRate >> 16) & 0xff,
        (byteRate >> 24) & 0xff,
        // Uhm
        ((16 * channels) / 8).round(), 0,
        // bitsize
        16, 0,
        // "data"
        100, 97, 116, 97,
        size & 0xff,
        (size >> 8) & 0xff,
        (size >> 16) & 0xff,
        (size >> 24) & 0xff,
        ...data,
      ]);
      recordedFile.writeAsBytesSync(header, flush: true, mode: FileMode.write);
      segmentWaveFile(filename);
    } else {
      print('local storage directory does not exist.');
    }
  }

  Future<List<String>> getSpeakerFiles(String directoryPath) async {
    // Create a Directory object
    final directory = Directory(directoryPath);

    // List to store file paths
    List<String> filePaths = [];

    // Check if the directory exists
    if (await directory.exists()) {
      // Use the list method to get all files and directories
      await for (var entity in directory.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is File) {
          filePaths.add(entity.path); // Add file paths to the list
        }
      }

      // Print the list of file paths
      print('Files in directory:');
      filePaths.forEach(print);
    } else {
      print('Directory does not exist.');
    }
    return filePaths;
  }

  Future<List<String>> getSpeakerDirectories(String directoryPath) async {
    // Create a Directory object
    final directory = Directory(directoryPath);

    // List to store file paths
    List<String> directoryPaths = [];

    // Check if the directory exists
    if (await directory.exists()) {
      // Use the list method to get all files and directories
      await for (var entity in directory.list(
        recursive: false,
        followLinks: false,
      )) {
        if (entity is Directory) {
          directoryPaths.add(entity.path); // Add file paths to the list
        }
      }

      // Print the list of file paths
      print('Directories in directory:');
      directoryPaths.forEach(print);
    } else {
      print('Directory does not exist.');
    }
    return directoryPaths;
  }

  Future<void> registerSpeakers(
    Directory directory,
    sherpa_onnx.SpeakerEmbeddingExtractor extractor,
    sherpa_onnx.SpeakerEmbeddingManager manager,
  ) async {
    List<List<Float32List>> speakerVectors = [];
    List<String> speakerFolders = await getSpeakerDirectories(
      '${directory.path}/voice_samples/',
    );
    List<String> names = [];
    for (int i = 0; i < speakerFolders.length; i++) {
      speakerVectors.add([]);
      names.add(Path.basename(speakerFolders[i]));
      List<String> speakerFiles = await getSpeakerFiles(speakerFolders[i]);
      for (var file in speakerFiles) {
        Float32List embedding = computeEmbedding(
          extractor: extractor,
          filename: file,
        );
        speakerVectors[i].add(embedding);
      }
    }
    for (int k = 0; k < speakerVectors.length; k++) {
      if (!manager.addMulti(name: names[k], embeddingList: speakerVectors[k])) {
        print('Failed to register ${names[k]}');
      }
      print('REGISTERED: ${names[k]}');
    }
  }

  Future<void> segmentWaveFile(String waveFilename) async {
    final segmentationModel = await copyAssetFile(
      "assets/sherpa-onnx-pyannote-segmentation-3-0/model.onnx",
    );
    final embeddingModel = await copyAssetFile(
      "assets/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx",
    );

    final segmentationConfig =
        sherpa_onnx.OfflineSpeakerSegmentationModelConfig(
      pyannote: sherpa_onnx.OfflineSpeakerSegmentationPyannoteModelConfig(
        model: segmentationModel,
      ),
    );

    final embeddingConfig = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
      model: embeddingModel,
    );
    final extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
      config: embeddingConfig,
    );
    final manager = sherpa_onnx.SpeakerEmbeddingManager(extractor.dim);

    Directory? directory = await getExternalStorageDirectory();
    if (directory != null) {
      await registerSpeakers(directory, extractor, manager);
    }
    print("ALL SPEAKERS REGISTERED");
    // since we know there are 4 speakers in ./0-four-speakers-zh.wav, we set
    // numClusters to 4. If you don't know the exact number, please set it to -1.
    // in that case, you have to set threshold. A larger threshold leads to
    // fewer clusters, i.e., fewer speakers.
    final clusteringConfig = sherpa_onnx.FastClusteringConfig(
      numClusters: 4,
      threshold: 0.5,
    );

    var config = sherpa_onnx.OfflineSpeakerDiarizationConfig(
      segmentation: segmentationConfig,
      embedding: embeddingConfig,
      clustering: clusteringConfig,
      minDurationOn: 0.2,
      minDurationOff: 0.5,
    );

    final sd = sherpa_onnx.OfflineSpeakerDiarization(config);
    if (sd.ptr == nullptr) {
      return;
    }

    final waveData = sherpa_onnx.readWave(waveFilename);

    if (sd.sampleRate != waveData.sampleRate) {
      print(
        'Expected sample rate: ${sd.sampleRate}, given: ${waveData.sampleRate}',
      );
      return;
    }

    print('started');

    // Use the following statement if you don't want to use a callback
    // final segments = sd.process(samples: waveData.samples);
    final segments = sd.processWithCallback(
      samples: waveData.samples,
      callback: (int numProcessedChunk, int numTotalChunks) {
        final progress = 100.0 * numProcessedChunk / numTotalChunks;
        print('Progress ${progress.toStringAsFixed(2)}%');
        return 0;
      },
    );
    sd.free();
    if (segments.isNotEmpty) {
      _offlineRecognizer = await createOfflineRecognizer();
      for (int i = 0; i < segments.length; ++i) {
        print(
          '${segments[i].start.toStringAsFixed(3)} -- ${segments[i].end.toStringAsFixed(3)}  speaker_${segments[i].speaker}',
        );
        String outputFile = waveFilename.replaceFirst('.wav', '/$i.wav');
        await File(outputFile).create(recursive: true);
        await trimAudio(
          waveFilename,
          outputFile,
          segments[i],
          extractor,
          manager,
        );
      }
      _offlineRecognizer!.free();
      extractor.free();
      manager.free();
      _controller.value = TextEditingValue(
        text: _textToDisplay,
        selection: TextSelection.collapsed(offset: _textToDisplay.length),
      );

      //Delete Temporary Files
      if (directory != null) {
        File('${directory.path}/temporary.wav').delete();
        Directory('${directory.path}/temporary/').delete(recursive: true);
      }
    }
    setState(() {
      _isLoading = false;
      if (_textToDisplay.contains('speaker_')) {
        RegExp regex = RegExp(r'speaker_\d+');
        Iterable<Match> matches = regex.allMatches(_textToDisplay);
        _speakerList = matches.map((match) => match.group(0)!).toSet().toList();
      }
    });
  }

  // Trim audio file
  Future<void> trimAudio(
    String inputPath,
    String outputPath,
    sherpa_onnx.OfflineSpeakerDiarizationSegment segment,
    sherpa_onnx.SpeakerEmbeddingExtractor extractor,
    sherpa_onnx.SpeakerEmbeddingManager manager,
  ) async {
    try {
      //await SimpleAudioTrimmer.trim(
      //  inputPath: inputPath,
      //  outputPath: outputPath,
      //  start: segment.start,
      //  end: segment.end,
      //);
      await offlineSpeechRecognizer(
        outputPath,
        segment.speaker,
        extractor,
        manager,
      );
    } on PlatformException catch (e) {
      print(e.message);
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> offlineSpeechRecognizer(
    String waveFilename,
    int speaker,
    sherpa_onnx.SpeakerEmbeddingExtractor extractor,
    sherpa_onnx.SpeakerEmbeddingManager manager,
  ) async {
    final waveData = sherpa_onnx.readWave(waveFilename);
    final stream = _offlineRecognizer!.createStream();
    stream.acceptWaveform(
      samples: waveData.samples,
      sampleRate: waveData.sampleRate,
    );
    _offlineRecognizer!.decode(stream);
    final result = _offlineRecognizer!.getResult(stream);
    final embedding = computeEmbedding(
      extractor: extractor,
      filename: waveFilename,
    );
    var name = manager.search(embedding: embedding, threshold: .6);
    if (name == '') {
      name = 'speaker_$speaker';
    }
    setState(() {
      _textToDisplay += '$name: ${result.text}\n';
    });

    stream.free();
  }

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(encoder);

    if (!isSupported) {
      debugPrint('${encoder.name} is not supported on this platform.');
      debugPrint('Supported encoders are:');

      for (final e in AudioEncoder.values) {
        if (await _audioRecorder.isEncoderSupported(e)) {
          debugPrint('- ${encoder.name}');
        }
      }
    }

    return isSupported;
  }

  Future<void> _saveRecognizedText() async {
    if (_textToDisplay.trim().isEmpty) {
      return;
    }

    final createdNote = PatientNote(
      id: '',
      patientId: widget.patientId!,
      note: _textToDisplay,
      aiSummary: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

    try {
      PatientNote newNote = await NotetakerConfigService.createPatientNote(
        createdNote,
      );

      setState(() {
        _noteSaved = true;
        _savedNote = newNote;
      });

      if (widget.onUploadSuccess != null) {
        widget.onUploadSuccess!(newNote);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note saved'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save note: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _isLoading
            ? Column(
                children: [CircularProgressIndicator(), Text("Processing")],
              )
            : TextField(
                maxLines: 5,
                controller: _controller,
                readOnly: true,
                scrollController: _scrollController,
              ),
        const SizedBox(height: 16),
        if (!_noteSaved) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildRecordStopControl(),
              const SizedBox(width: 16),
              _buildText(),
            ],
          ),
          const SizedBox(height: 16),
          _speakerList.isNotEmpty
              ? ElevatedButton(
                  child: const Text('Swap Speaker Names'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return Expanded(
                          child: SimpleDialog(
                            title: Text("Swap Speaker Names"),
                            children: <Widget>[
                              Padding(
                                padding: EdgeInsets.all(10.0),
                                child: DropdownButtonFormField<String>(
                                  initialValue: _selectedSpeaker,
                                  decoration: InputDecoration(
                                    labelText: 'Select A Speaker',
                                  ),
                                  items: _speakerList
                                      .map(
                                        (option) => DropdownMenuItem(
                                          value: option,
                                          child: Text(option),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedSpeaker = value;
                                    });
                                  },
                                  validator: (value) {
                                    if (value == null) {
                                      return 'Please select an option';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              Icon(Icons.swap_vert),
                              SizedBox(width: 12),
                              Padding(
                                padding: EdgeInsets.all(10.0),
                                child: TextFormField(
                                  controller: _newSpeakerName,
                                  decoration: InputDecoration(
                                    labelText: 'Enter Name',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'This field is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              SizedBox(width: 12),
                              SimpleDialogOption(
                                onPressed: () {
                                  if (_selectedSpeaker != null &&
                                      _newSpeakerName.text.isNotEmpty) {
                                    setState(() {
                                      _textToDisplay =
                                          _textToDisplay.replaceAll(
                                        _selectedSpeaker!,
                                        _newSpeakerName.text,
                                      );
                                      _controller.value = TextEditingValue(
                                        text: _textToDisplay,
                                        selection: TextSelection.collapsed(
                                          offset: _textToDisplay.length,
                                        ),
                                      );
                                    });
                                    Navigator.of(context).pop();
                                  }
                                },
                                child: const Text('Swap'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                )
              : SizedBox.shrink(),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isLoading || _textToDisplay.isEmpty
                ? null
                : () => _saveRecognizedText(),
            child: const Text('Save Note'),
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await context.push(
                    '/notetaker/detail/${_savedNote!.id}',
                    extra: _savedNote,
                  );
                  setState(() {
                    _noteSaved = false;
                    _savedNote = null;
                    _textToDisplay = '';
                    _controller.clear();
                    _speakerList = [];
                    _selectedSpeaker = null;
                    _newSpeakerName.clear();
                  });
                },
                child: const Text('View Summary'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _noteSaved = false;
                    _savedNote = null;
                    _textToDisplay = '';
                    _controller.clear();
                    _speakerList = [];
                    _selectedSpeaker = null;
                    _newSpeakerName.clear();
                  });
                },
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                child: const Text('Listen Again'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _audioRecorder.dispose();
    _stream?.free();
    _recognizer?.free();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildRecordStopControl() {
    late Icon icon;
    late Color color;

    if (_recordState != RecordState.stop) {
      icon = const Icon(Icons.stop, color: Colors.red, size: 30);
      color = Colors.red.withOpacity(0.1);
    } else {
      final theme = Theme.of(context);
      icon = Icon(Icons.mic, color: theme.primaryColor, size: 30);
      color = theme.primaryColor.withOpacity(0.1);
    }

    return ClipOval(
      child: Material(
        color: color,
        child: InkWell(
          child: SizedBox(width: 56, height: 56, child: icon),
          onTap: () {
            if (_recordState != RecordState.stop) {
              _stop();
            } else {
              _start();
            }
          },
        ),
      ),
    );
  }

  Widget _buildText() {
    if (_recordState == RecordState.stop) {
      return const Text("Start");
    } else {
      return const Text("Stop");
    }
  }
}
