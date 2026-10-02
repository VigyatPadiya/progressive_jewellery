import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MaterialApp(home: Scaffold(body: Center(child: TestWidget()))));
}

class TestWidget extends StatefulWidget {
  const TestWidget({super.key});

  @override
  State<TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<TestWidget> {
  String text = 'Running test...';

  @override
  void initState() {
    super.initState();
    _runTest();
  }

  Future<void> _runTest() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => text = 'Not logged in. Please log in the main app first.');
        return;
      }
      
      String out = 'UID: ${user.uid}\n\n';
      
      final doc = await FirebaseFirestore.instance.doc('stores/progressive-jewellery/members/${user.uid}').get();
      if (doc.exists) {
        out += 'Doc exists: ${doc.data()}\n\n';
      } else {
        out += 'Doc DOES NOT EXIST at stores/progressive-jewellery/members/${user.uid}\n\n';
        
        final stores = await FirebaseFirestore.instance.collection('stores').get();
        out += 'Collections in "stores": ${stores.docs.length}\n';
        for (var s in stores.docs) {
          out += ' - ${s.id}\n';
          
          try {
            final members = await FirebaseFirestore.instance.collection('stores/${s.id}/members').get();
            out += '   Members in ${s.id}: ${members.docs.length}\n';
            for (var m in members.docs) {
              out += '    - ${m.id} : ${m.data()}\n';
            }
          } catch(e) {
            out += '   Cannot read members for ${s.id}: $e\n';
          }
        }
        
        // Also let's check progressive-jewellery/members
        try {
          final members2 = await FirebaseFirestore.instance.collection('progressive-jewellery/members/members').get();
          out += '\nCollection progressive-jewellery/members/members docs: ${members2.docs.length}\n';
          for (var m in members2.docs) {
            out += '    - ${m.id} : ${m.data()}\n';
          }
        } catch (e) {
          out += '\nCould not read progressive-jewellery/members/members: $e\n';
        }
      }
      
      setState(() => text = out);
    } catch (e) {
      setState(() => text = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectableText(text);
  }
}
