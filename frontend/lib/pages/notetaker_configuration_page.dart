import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notetaker_config_service.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;
import 'package:record/record.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:accordion/accordion.dart';

class NotetakerConfigurationPage extends StatefulWidget {
  const NotetakerConfigurationPage({super.key});

  @override
  State<NotetakerConfigurationPage> createState() =>
      _NotetakerConfigurationPageState();
}

class _NotetakerConfigurationPageState
    extends State<NotetakerConfigurationPage> {
  PatientNotetakerConfigDTO? _currentConfig;
  bool _isLoading = true;
  bool _isSaving = false;
  UserSession? _user;
  List<Map<String, String>> _patientList = [];
  String? _selectedPatientId;
  bool _isPatient = false;
  bool _isEnabled = true;
  bool _permitCaregiverAccess = false;
  List<String> _PIIList = [];
  List<String> _directories = [];
  late List<Widget> _PIIWidgetList = stringToCard(_PIIList);
  late List<Widget> _DirectoryWidgetList = stringToAccordion(_directories);
  Map<String, String> keyword_Event = {};

  //Audio Recorder
  final int _sampleRate = 16000;
  late final AudioRecorder _audioRecorder;
  StreamSubscription<RecordState>? _recordSub;
  RecordState _recordState = RecordState.stop;
  List<int> recordedData = [];

  // Form controllers
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _PIIController = TextEditingController();
  final TextEditingController _fileNameController = TextEditingController();
  String? _selectedDropdownValue;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();
    _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
      _updateRecordState(recordState);
    });
    super.initState();
    _loadConfiguration();
  }

  void _updateRecordState(RecordState recordState) {
    setState(() => _recordState = recordState);
  }

  @override
  void dispose() {
    _recordSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  Widget _buildConfigForm() {
    final theme = Theme.of(context);
    List<Widget> childWidgets = [];
    final successText =
        'Configure your Notetaker assistant to recognize PII, trigger words, etc and upload voice samples for speaker recognition.';
    final failureText =
        'Configuration options cannot be displayed because either you have no patients or their was an error fetching them.';
    if (_isPatient) {
      childWidgets = [
        _buildInfoCard(theme, successText),
        const SizedBox(height: 24),
        _buildToggleSection(theme),
        const SizedBox(height: 24),
        _buildPIISection(theme),
        const SizedBox(height: 24),
        _buildKeywordSection(theme),
        const SizedBox(height: 24),
        _buildVoiceSampleSection(theme)
      ];
    } else if (_patientList.isEmpty) {
      childWidgets = [
        _buildInfoCard(theme, failureText),
      ];
    } else if (_selectedPatientId == null) {
      childWidgets = [
        _buildInfoCard(theme, successText),
        const SizedBox(height: 24),
        _buildPatientSection(theme),
      ];
    } else {
      childWidgets = [
        _buildInfoCard(theme, successText),
        const SizedBox(height: 24),
        _buildPatientSection(theme),
        const SizedBox(height: 24),
        _buildPIISection(theme),
        const SizedBox(height: 24),
        _buildKeywordSection(theme),
        const SizedBox(height: 24),
        _buildVoiceSampleSection(theme)
      ];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: childWidgets),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;
    if (user == null) {
      Future.microtask(() => context.go('/login'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text(
            'Notetaker Configuration',
            style: TextStyle(fontSize: 18),
          ),
        ]),
        actions: [
          TextButton(
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                  EdgeInsets.symmetric(horizontal: 5, vertical: 15)),
            ),
            onPressed: (_isLoading || _isSaving)
                ? null
                : () {
                    // Discard changes and navigate back
                    context.pop();
                  },
            child: const Text('Cancel'),
          ),
          TextButton(
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                  EdgeInsets.symmetric(horizontal: 5, vertical: 15)),
            ),
            onPressed: (_isLoading || _isSaving)
                ? null
                : () async {
                    await _saveConfiguration();
                  },
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildConfigForm(),
    );
  }

  List<Widget> stringToAccordion(List<String> directories) {
    List<Widget> namedVoices = [];
    for (int i = 0; i < directories.length; i++) {
      List<String> files = [];
      Directory voiceDirectory = Directory(directories[i]);
      String name = path.basename(directories[i]);
      if (voiceDirectory.existsSync()) {
        // Use the list method to get all files and directories
        for (var entity
            in voiceDirectory.listSync(recursive: false, followLinks: false)) {
          if (entity is File) {
            files.add(entity.path); // Add file paths to the list
          }
        }
        // Print the list of file paths
        print('Files in directory:');
        files.forEach(print);
      } else {
        print('Directory does not exist.');
      }
      if (files.isEmpty) {
        voiceDirectory.deleteSync(recursive: true);
      } else {
        namedVoices.add(Card(
            child: Padding(
                padding: EdgeInsets.all(10.0),
                child: Accordion(
                  headerBorderRadius: 50,
                  headerPadding: EdgeInsets.all(15.0),
                  children: [
                    AccordionSection(
                        header:
                            Text(name, style: TextStyle(color: Colors.white)),
                        content: Column(
                            children: files
                                .map((file) => Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: <Widget>[
                                          Text(path.basename(file),
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary)),
                                          IconButton(
                                              icon: Icon(Icons.cancel),
                                              tooltip: 'delete voice sample',
                                              onPressed: () {
                                                setState(() {
                                                  deleteVoiceSamples(
                                                      directories[i],
                                                      path.basename(file));
                                                });
                                              })
                                        ]))
                                .toList()))
                  ],
                ))));
      }
    }
    return namedVoices;
  }

  List<Widget> stringToCard(List<String> list) {
    return list
        .map((value) => Card(
            child: Padding(
                padding: EdgeInsets.all(10.0),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(value),
                      IconButton(
                          icon: Icon(Icons.cancel),
                          tooltip: 'delete PII',
                          onPressed: () {
                            setState(() {
                              _PIIList.remove(value);
                              _PIIWidgetList = stringToCard(list);
                            });
                          })
                    ]))))
        .toList();
  }

  List<DataRow> generateRows() {
    List<DataRow> rowList = [];
    keyword_Event.forEach((key, value) => rowList.add(DataRow(cells: [
          DataCell(Text(key)),
          DataCell(Text(value)),
          DataCell(IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              setState(() {
                keyword_Event.remove(key);
              });
            },
          ))
        ])));
    return rowList;
  }

  Widget _buildToggleCard(
    BuildContext context, {
    required String name,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void deleteVoiceSamples(String directory, String fileName) async {
    File sampleToDelete = File('$directory/$fileName');
    sampleToDelete.deleteSync();
    loadVoiceSamples();
  }

  void loadVoiceSamples() async {
    // Specify the directory path
    Directory? directory = await getExternalStorageDirectory();
    setState(() {
      _directories = [];
    });
    if (directory != null) {
      final voiceSampleDirectory =
          Directory('${directory.path}/voice_samples/');
      // Check if the directory exists
      if (await voiceSampleDirectory.exists()) {
        // List all entities (files and subdirectories) in the directory
        await for (var entity in voiceSampleDirectory.list(
            recursive: false, followLinks: false)) {
          if (entity is Directory) {
            // Read the file content
            setState(() {
              _directories.add(entity.path);
            });
          }
        }
        setState(() {
          _DirectoryWidgetList = stringToAccordion(_directories);
        });
      } else {
        print('Voice Sample Directory does not exist.');
      }
    }
  }

  Future<bool> _isEncoderSupported(AudioEncoder encoder) async {
    final isSupported = await _audioRecorder.isEncoderSupported(
      encoder,
    );

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

  Future<void> _startListening() async {
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
      recordedData = [];
      final stream = await _audioRecorder.startStream(config);
      stream.listen(
        (data) {
          recordedData.addAll(data);
        },
        onDone: () {
          print('stream stopped.');
        },
      );
    }
  }

  void _stopListening() async {
    await _audioRecorder.stop();
  }

  Future<void> saveFile(List<int> data, int sampleRate, String file) async {
    Directory? directory = await getExternalStorageDirectory();
    String filename = "";
    if (directory != null) {
      filename =
          "${directory.path}/voice_samples/$file/$file-${DateTime.now().millisecondsSinceEpoch}.wav";
      File recordedFile = await File(filename).create(recursive: true);

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
        ...data
      ]);
      recordedFile.writeAsBytesSync(header, flush: true, mode: FileMode.write);
      loadVoiceSamples();
    } else {
      print('local storage directory does not exist.');
    }
  }

  Future<void> _fetchConfig(int patientId) async {
    try {
      final config = await NotetakerConfigService.getUserNotetakerConfig(
          patientId, context);
      if (config != null) {
        setState(() {
          _currentConfig = config;
          _isEnabled = config.isEnabled;
          _permitCaregiverAccess = config.permitCaregiverAccess;
          _PIIList = config.triggerKeywords
              .where((trigger) => trigger.keyword.contains("PII_"))
              .map((trigger) => trigger.keyword.replaceAll("PII_", ""))
              .toList();
          keyword_Event = {};
          config.triggerKeywords
              .where((trigger) => !trigger.keyword.contains("PII_"))
              .forEach((trigger) =>
                  keyword_Event[trigger.keyword] = trigger.event_type);
          _PIIWidgetList = stringToCard(_PIIList);
        });
        if (!kIsWeb) {
          loadVoiceSamples();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load Notetaker configuration: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadConfiguration() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      setState(() {
        _user = userProvider.user;
        if (_user == null) throw Exception('User not found');
        final userRole = _user!.role;
        _isPatient = userRole.toUpperCase() == 'PATIENT';
      });
      if (!_isPatient && _user!.caregiverId != null) {
        http.Response patientResponse =
            await ApiService.getCaregiverPatients(_user!.caregiverId!);
        setState(() {
          _patientList = (jsonDecode(patientResponse.body) as List<dynamic>)
              .map((patientWLink) => {
                    'id': patientWLink['patient']['id'].toString(),
                    'name':
                        '${patientWLink['patient']['firstName']} ${patientWLink['patient']['lastName']}'
                  })
              .toList();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load user profile: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    if (_isPatient) {
      _fetchConfig(_user!.patientId!);
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveConfiguration() async {
    setState(() => _isSaving = true);
    try {
      if (_user == null) throw Exception('User not found');
      List<PatientNotetakerKeyword> keywordList = [];
      for (var pii in _PIIList) {
        keywordList.add(
            PatientNotetakerKeyword(keyword: 'PII_$pii', event_type: 'ALERT'));
      }
      keyword_Event.forEach((keyword, event) => keywordList
          .add(PatientNotetakerKeyword(keyword: keyword, event_type: event)));
      final config = PatientNotetakerConfigDTO(
        id: _currentConfig?.id,
        patientId: _isPatient
            ? _user!.patientId!
            : int.parse(_selectedPatientId ?? '-1'),
        isEnabled: _isEnabled,
        permitCaregiverAccess: _permitCaregiverAccess,
        triggerKeywords: keywordList,
      );
      // Use NotetakerConfigService to update config
      final savedConfig = await NotetakerConfigService.saveUserNotetakerConfig(
        config,
        userId: _user!.id,
      );

      if (savedConfig != null) {
        setState(() => _currentConfig = savedConfig);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  const Text('Notetaker configuration saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Failed to save configuration');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save configuration: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildInfoCard(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primaryContainer, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientSection(ThemeData theme) {
    return _buildSection(
        theme,
        'Select patient',
        Icons.person, // Changed from Icons.psychology for better compatibility
        [
          DropdownButtonFormField<String>(
            initialValue: _selectedPatientId,
            decoration: InputDecoration(labelText: 'Select an option'),
            items: _patientList
                .map((patient) => DropdownMenuItem(
                      value: patient['id'],
                      child: Text(patient['name']!),
                    ))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedPatientId = value!;
              });
              _fetchConfig(int.parse(_selectedPatientId!));
            },
            validator: (value) {
              if (value == null) {
                return 'Please select an option';
              }
              return null;
            },
          ),
        ]);
  }

  Widget _buildToggleSection(ThemeData theme) {
    return _buildSection(
        theme,
        'Enable Usage/Access',
        Icons.person, // Changed from Icons.psychology for better compatibility
        [
          _buildToggleCard(context,
              name: 'Enable Notetaker Assistant',
              value: _isEnabled,
              onChanged: (value) => {
                    setState(() {
                      _isEnabled = !_isEnabled;
                    })
                  }),
          SizedBox(height: 16),
          _buildToggleCard(context,
              name: 'Enable Caregiver Access',
              value: _permitCaregiverAccess,
              onChanged: (value) => {
                    setState(() {
                      _permitCaregiverAccess = !_permitCaregiverAccess;
                    })
                  })
        ]);
  }

  Widget _buildPIISection(ThemeData theme) {
    return _buildSection(
      theme,
      'PII terms',
      Icons.warning,
      [
        SizedBox(
            height: 250,
            child: ListView.builder(
              itemCount: _PIIWidgetList.length,
              itemBuilder: (context, index) {
                return _PIIWidgetList[index];
              },
            )),
        TextButton.icon(
            onPressed: () {
              _PIIController.clear();
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Expanded(
                    child: SimpleDialog(
                        title: Text("Add a PII term"),
                        children: <Widget>[
                          Padding(
                            padding: EdgeInsets.all(10.0),
                            child: TextFormField(
                              controller: _PIIController,
                              decoration:
                                  InputDecoration(labelText: 'Enter text'),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'This field is required';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(height: 16),
                          SimpleDialogOption(
                            onPressed: () {
                              setState(() {
                                _PIIList.add(_PIIController.text);
                                _PIIWidgetList = stringToCard(_PIIList);
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Add'),
                          )
                        ]),
                  );
                },
              );
            },
            icon: Icon(Icons.add, size: 24),
            label: Text('Add PII'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            )),
      ],
    );
  }

  Widget _buildKeywordSection(ThemeData theme) {
    return _buildSection(
      theme,
      'Keywords',
      Icons.key,
      [
        SizedBox(
            height: 250,
            child: LayoutBuilder(builder: (context, constraints) {
              return SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                          columnSpacing: 16.0,
                          columns: [
                            DataColumn(label: Expanded(child: Text("Keyword"))),
                            DataColumn(
                                label: Expanded(child: Text("Event Type"))),
                            DataColumn(label: Expanded(child: Text("")))
                          ],
                          rows: generateRows())));
            })),
        SizedBox(
          height: 16,
        ),
        TextButton.icon(
            onPressed: () {
              _keywordController.clear();
              _selectedDropdownValue = null;
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Expanded(
                    child: SimpleDialog(
                        title: Text("Add a keyword"),
                        children: <Widget>[
                          Padding(
                              padding: EdgeInsets.all(10.0),
                              child: TextFormField(
                                controller: _keywordController,
                                decoration:
                                    InputDecoration(labelText: 'Enter text'),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'This field is required';
                                  }
                                  return null;
                                },
                              )),
                          SizedBox(width: 12),
                          Padding(
                            padding: EdgeInsets.all(10.0),
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedDropdownValue,
                              decoration: InputDecoration(
                                  labelText: 'Select an option'),
                              items: ['ALERT', 'TASK']
                                  .map((option) => DropdownMenuItem(
                                        value: option,
                                        child: Text(option),
                                      ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDropdownValue = value;
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
                          SimpleDialogOption(
                            onPressed: () {
                              setState(() {
                                if (_selectedDropdownValue != null) {
                                  keyword_Event[_keywordController.text] =
                                      _selectedDropdownValue as String;
                                }
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Add'),
                          )
                        ]),
                  );
                },
              );
            },
            icon: Icon(Icons.add, size: 24),
            label: Text('Add Keyword'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            )),
      ],
    );
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
            (_recordState != RecordState.stop)
                ? _stopListening()
                : _startListening();
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

  Widget _buildVoiceSampleSection(ThemeData theme) {
    if (kIsWeb) {
      return _buildSection(theme, 'Manage Voice Sample', Icons.voice_chat, [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withOpacity(0.1),
          ),
          child: Column(
            children: [
              Icon(Icons.cancel_outlined,
                  color: theme.colorScheme.primary, size: 48),
              const SizedBox(width: 12),
              Text(
                'This feature is not available on the web application',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                ),
              )
            ],
          ),
        ),
      ]);
    } else {
      return _buildSection(
        theme,
        'Manage Voice Sample',
        Icons.voice_chat,
        [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withOpacity(0.1),
            ),
            child: Column(
              children: [
                _buildInfoCard(
                    theme,
                    'Tap the button below to start voice recognition. '
                    'The more voice samples provided the more accurate speaker identification will be.'
                    'Try saying the phrases: "The birch canoe slid on the smooth planks", "Glue the sheet to the dark blue background.", "It’s easy to tell the depth of a well.", '
                    '"These days a chicken leg is a rare dish."'),
                const SizedBox(height: 16),
                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _buildRecordStopControl(),
                      const SizedBox(width: 16),
                      _buildText(),
                    ]),
                ElevatedButton(
                    onPressed: recordedData.isEmpty
                        ? null
                        : () {
                            _fileNameController.clear();
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return Expanded(
                                  child: SimpleDialog(
                                      title: Text("Enter your name"),
                                      children: <Widget>[
                                        Padding(
                                          padding: EdgeInsets.all(10.0),
                                          child: TextFormField(
                                            controller: _fileNameController,
                                            decoration: InputDecoration(
                                                labelText: 'Enter text'),
                                            validator: (value) {
                                              if (value == null ||
                                                  value.isEmpty) {
                                                return 'This field is required';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        SizedBox(height: 16),
                                        SimpleDialogOption(
                                          onPressed: () {
                                            if (_fileNameController
                                                .text.isNotEmpty) {
                                              saveFile(
                                                  recordedData,
                                                  _sampleRate,
                                                  _fileNameController.text);
                                              Navigator.of(context).pop();
                                            }
                                          },
                                          child: const Text('Add'),
                                        )
                                      ]),
                                );
                              },
                            );
                          },
                    child: Text('Save File')),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
              height: 250,
              child: ListView.builder(
                itemCount: _DirectoryWidgetList.length,
                itemBuilder: (context, index) {
                  return _DirectoryWidgetList[index];
                },
              )),
        ],
      );
    }
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}
