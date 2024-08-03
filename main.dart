import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
final appDocumentDirectory = await path_provider.getApplicationDocumentsDirectory();
await Hive.initFlutter(appDocumentDirectory.path);
Hive.registerAdapter(NoteCardAdapter());

const secureStorage = FlutterSecureStorage();
var encryptionKeyString = await secureStorage.read(key: 'encryptionKey');
List<int> encryptionKey;

if (encryptionKeyString == null) {
encryptionKey = Hive.generateSecureKey();
await secureStorage.write(key: 'encryptionKey', value: base64UrlEncode(encryptionKey));
} else {
encryptionKey = base64Url.decode(encryptionKeyString);
}

await Hive.openBox<NoteCard>(
'libera',
encryptionCipher: HiveAesCipher(encryptionKey),
);

runApp(const MyApp());
}

class MyApp extends StatelessWidget {
const MyApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'libera',
theme: ThemeData.light(),
darkTheme: ThemeData.dark(),
themeMode: ThemeMode.system,
home: const MyHomePage(),
);
}
}

class MyHomePage extends StatefulWidget {
const MyHomePage({super.key});

@override
State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
late Box<NoteCard> _box;
final TextEditingController _searchController = TextEditingController();
final Map<String, TextEditingController> _controllers = {};
final Map<String, FocusNode> _focusNodes = {};
Timer? _debounce;
bool _isFabVisible = true;

@override
void initState() {
super.initState();
_box = Hive.box<NoteCard>('libera');
_searchController.addListener(_onSearchChanged);
}

@override
void dispose() {
_searchController.removeListener(_onSearchChanged);
_searchController.dispose();
_debounce?.cancel();
for (var controller in _controllers.values) {
controller.dispose();
}
for (var focusNode in _focusNodes.values) {
focusNode.dispose();
}
super.dispose();
}

List<NoteCard> _getFilteredNoteCards(String searchText) {
if (searchText.isEmpty) {
return _box.values.toList();
} else {
return _box.values.where((card) {
return card.content.toLowerCase().contains(searchText.toLowerCase());
}).toList();
}
}

Future<void> _deleteCard(NoteCard card) async {
await card.delete();
setState(() {});
}

Future<void> _addNewCard() async {
final newCard = NoteCard('');
await _box.add(newCard);
setState(() {});

WidgetsBinding.instance.addPostFrameCallback((_) {
_focusNodes[newCard.key.toString()]?.requestFocus();
});
}

TextEditingController _getController(String key, String initialText) {
if (!_controllers.containsKey(key)) {
_controllers[key] = TextEditingController(text: initialText);
}
return _controllers[key]!;
}

FocusNode _getFocusNode(String key) {
if (!_focusNodes.containsKey(key)) {
_focusNodes[key] = FocusNode();
}
return _focusNodes[key]!;
}

void _onSearchChanged() {
if (_debounce?.isActive ?? false) _debounce?.cancel();
_debounce = Timer(const Duration(milliseconds: 300), () {
setState(() {});
});
}

void _showDeleteConfirmation(BuildContext context, NoteCard card) async {
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
builder: (context) {
return Container(
padding: const EdgeInsets.all(18.0),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
ListTile(
leading: const Icon(Icons.delete),
title: const Text('Удалить'),
onTap: () {
Navigator.pop(context);
_showDeleteConfirmation(context, card);
},
),
],
),
);
},
);
}

void _toggleFabVisibility(bool visible) {
setState(() {
_isFabVisible = visible;
});
}

void _cleanupControllers(List<NoteCard> currentCards) {
_controllers.removeWhere((key, controller) {
if (!currentCards.any((card) => card.key.toString() == key)) {
controller.dispose();
return true;
}
return false;
});

_focusNodes.removeWhere((key, focusNode) {
if (!currentCards.any((card) => card.key.toString() == key)) {
focusNode.dispose();
return true;
}
return false;
});
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: const Text('Либера'),
shape: const RoundedRectangleBorder(
borderRadius: BorderRadius.vertical(
bottom: Radius.circular(8),
),
),
),
body: Column(
children: [
Padding(
padding: const EdgeInsets.all(8.0),
child: TextField(
controller: _searchController,
decoration: const InputDecoration(
labelText: 'Поиск',
prefixIcon: Icon(Icons.search),
),
),
),
Expanded(
child: ValueListenableBuilder<Box<NoteCard>>(
valueListenable: _box.listenable(),
builder: (context, box, child) {
final filteredNoteCards = _getFilteredNoteCards(_searchController.text);
_cleanupControllers(filteredNoteCards);
return ListView.builder(
itemCount: filteredNoteCards.length,
itemBuilder: (context, index) {
final card = filteredNoteCards[index];
final textController = _getController(card.key.toString(), card.content);
final focusNode = _getFocusNode(card.key.toString());

return Card(
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(4),
),
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
onPressed: () {
_showBottomSheet(context, card);
},
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
},
);
},
),
),
],
),
floatingActionButton: MouseRegion(
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
),
);
}
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
NoteCard read(BinaryReader reader) {
return NoteCard(reader.read());
}

@override
void write(BinaryWriter writer, NoteCard obj) {
writer.write(obj.content);
}
}