import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as path_provider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appDocumentDirectory =
      await path_provider.getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDirectory.path);
  Hive.registerAdapter(NoteCardAdapter());
  await Hive.openBox<NoteCard>('libera');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'libera',
      theme: ThemeData(
        primarySwatch: MaterialColor(0xFF92a8a3, {
          50: Color(0xFFe2eeed),
          100: Color(0xFFc6ddd9),
          200: Color(0xFFa7cac4),
          300: Color(0xFF89b8af),
          400: Color(0xFF6da7a0),
          500: Color(0xFF92a8a3),
          600: Color(0xFF57948b),
          700: Color(0xFF46847a),
          800: Color(0xFF366369),
          900: Color(0xFF254357),
        }),
      ),
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  ScrollController _scrollController = ScrollController();
  final Box<NoteCard> box = Hive.box<NoteCard>('libera');
  final List<TextEditingController> textControllers = [];
  String searchText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    Hive.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<NoteCard> getFilteredNoteCards() {
    if (searchText.isEmpty) {
      return box.values.toList();
    } else {
      return box.values.where((card) {
        return card.content.toLowerCase().contains(searchText.toLowerCase());
      }).toList();
    }
  }

  List<TextEditingController> getFilteredTextControllers() {
    final filteredNoteCards = getFilteredNoteCards();

    if (filteredNoteCards.isEmpty) {
      textControllers.clear();
    } else if (filteredNoteCards.length != textControllers.length) {
      textControllers.clear();
      textControllers.addAll(List.generate(
          filteredNoteCards.length, (index) => TextEditingController()));
    }

    return textControllers;
  }

  void deleteCard(int index, BuildContext context) {
    final noteCard = getFilteredNoteCards()[index];

    setState(() {
      textControllers.removeAt(index);
      box.delete(noteCard.key);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Note card deleted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredNoteCards = getFilteredNoteCards();
    final filteredTextControllers = getFilteredTextControllers();

    return Scaffold(
      appBar: AppBar(
        title: Text('Либера'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  searchText = value;
                });
              },
              decoration: InputDecoration(
                labelText: 'Поиск',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: filteredNoteCards.length,
              itemBuilder: (context, index) {
                final card = filteredNoteCards[index];
                final textController = filteredTextControllers[index];
                textController.text = card.content;

                return Builder(
                  builder: (BuildContext context) {
                    return Dismissible(
                      key: UniqueKey(),
                      direction: DismissDirection.startToEnd,
                      background: Container(
                        alignment: AlignmentDirectional.centerStart,
                        color: Colors.red,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(0.0, 0.0, 10.0, 0.0),
                          child: Icon(
                            Icons.delete,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      onDismissed: (direction) {
                        deleteCard(index, context);
                      },
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 10),
                        child: ListTile(
                          title: Container(
                            color: Color(0xFFfae4cd),
                            child: TextField(
                              controller: textController,
                              maxLines: 7,
                              onChanged: (value) {
                                box.put(card.key.toString(), NoteCard(value));
                              },
                            ),
                          ),
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
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final newCard = NoteCard('Новая заметка');
          final newCardKey = await box.add(newCard);

          setState(() {
            textControllers.add(TextEditingController());
          });
          // Remove existing text controllers from the list
          textControllers.removeWhere((controller) =>
              controller.text.isEmpty || controller.text == 'Новая заметка');

          // Scroll to the new note card
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
        child: Icon(Icons.add),
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
  final typeId = 0;

  @override
  NoteCard read(BinaryReader reader) {
    return NoteCard(reader.read());
  }

  @override
  void write(BinaryWriter writer, NoteCard obj) {
    writer.write(obj.content);
  }
}
