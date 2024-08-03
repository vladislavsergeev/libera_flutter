import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';

Future<void> main() async {
  await initializeApp();
  runApp(const MyApp());
}

Future<void> initializeApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDirectory = await path_provider.getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDirectory.path);
  Hive.registerAdapter(NoteCardAdapter());

  final encryptionKey = await getOrCreateEncryptionKey();

  await Hive.openBox<NoteCard>(
    'libera',
    encryptionCipher: HiveAesCipher(encryptionKey),
  );
}

Future<List<int>> getOrCreateEncryptionKey() async {
  const secureStorage = FlutterSecureStorage();
  final encryptionKeyString = await secureStorage.read(key: 'encryptionKey');

  if (encryptionKeyString == null) {
    final encryptionKey = Hive.generateSecureKey();
    await secureStorage.write(key: 'encryptionKey', value: base64UrlEncode(encryptionKey));
    return encryptionKey;
  } else {
    return base64Url.decode(encryptionKeyString);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'libera',
    theme: ThemeData.light(),
    darkTheme: ThemeData.dark(),
    themeMode: ThemeMode.system,
    home: const MyHomePage(),
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final Box<NoteCard> _box;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  Timer? _debounce;
  bool _isFabVisible = true;
  List<NoteCard> _filteredNoteCards = [];

  @override
  void initState() {
    super.initState();
    _box = Hive.box<NoteCard>('libera');
    _searchController.addListener(_onSearchChanged);
    _updateFilteredNoteCards();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _disposeControllersAndFocusNodes();
    super.dispose();
  }

  void _disposeControllersAndFocusNodes() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }

  void _updateFilteredNoteCards() {
    final searchText = _searchController.text.toLowerCase();
    _filteredNoteCards = searchText.isEmpty
        ? _box.values.toList()
        : _box.values.where((card) => card.content.toLowerCase().contains(searchText)).toList();
  }

  Future<void> _deleteCard(NoteCard card) async {
    await card.delete();
    _updateFilteredNoteCards();
    setState(() {});
  }

  Future<void> _addNewCard() async {
    final newCard = NoteCard('');
    await _box.add(newCard);
    _updateFilteredNoteCards();
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[newCard.key.toString()]?.requestFocus();
    });
  }

  TextEditingController _getController(String key, String initialText) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: initialText));

  FocusNode _getFocusNode(String key) =>
      _focusNodes.putIfAbsent(key, () => FocusNode());

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _updateFilteredNoteCards();
      setState(() {});
    });
  }

  Future<void> _showDeleteConfirmation(BuildContext context, NoteCard card) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удаление заметки'),
        content: const Text('Удаляем заметку?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteCard(card);
    }
  }

  void _showBottomSheet(BuildContext context, NoteCard card) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(18.0),
        child: ListTile(
          leading: const Icon(Icons.delete),
          title: const Text('Удалить'),
          onTap: () {
            Navigator.pop(context);
            _showDeleteConfirmation(context, card);
          },
        ),
      ),
    );
  }

  void _toggleFabVisibility(bool visible) {
    setState(() => _isFabVisible = visible);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _buildAppBar(),
    body: Column(
      children: [
        _buildSearchField(),
        Expanded(child: _buildNoteList()),
      ],
    ),
    floatingActionButton: _buildFloatingActionButton(),
  );

  PreferredSizeWidget _buildAppBar() => AppBar(
    title: const Text('Либера'),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        bottom: Radius.circular(8),
      ),
    ),
  );

  Widget _buildSearchField() => Padding(
    padding: const EdgeInsets.all(8.0),
    child: TextField(
      controller: _searchController,
      decoration: const InputDecoration(
        labelText: 'Поиск',
        prefixIcon: Icon(Icons.search),
      ),
    ),
  );

  Widget _buildNoteList() => ValueListenableBuilder<Box<NoteCard>>(
    valueListenable: _box.listenable(),
    builder: (context, box, _) => ListView.builder(
      itemCount: _filteredNoteCards.length,
      itemBuilder: (context, index) => _buildNoteCard(_filteredNoteCards[index]),
    ),
  );

  Widget _buildNoteCard(NoteCard card) {
    final textController = _getController(card.key.toString(), card.content);
    final focusNode = _getFocusNode(card.key.toString());

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () => _showBottomSheet(context, card),
              ),
            ),
            TextField(
              controller: textController,
              focusNode: focusNode,
              maxLines: null,
              onChanged: (value) {
                card.content = value;
                card.save();
              },
              decoration: const InputDecoration(
                hintText: 'Новая заметка',
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() => MouseRegion(
    onEnter: (_) => _toggleFabVisibility(true),
    onExit: (_) => _toggleFabVisibility(false),
    child: AnimatedOpacity(
      opacity: _isFabVisible ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 300),
      child: FloatingActionButton(
        shape: const CircleBorder(),
        onPressed: _addNewCard,
        child: const Icon(Icons.add),
      ),
    ),
  );
}

@HiveType(typeId: 0)
class NoteCard extends HiveObject {
  @HiveField(0)
  String content;

  NoteCard(this.content);
}

class NoteCardAdapter extends TypeAdapter<NoteCard> {
  @override
  final int typeId = 0;

  @override
  NoteCard read(BinaryReader reader) => NoteCard(reader.read());

  @override
  void write(BinaryWriter writer, NoteCard obj) => writer.write(obj.content);
}