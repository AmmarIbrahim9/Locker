import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  List<File> _mediaFiles = [];
  String? _pin;
  bool _isLocked = true;
  bool _isBiometricAuthEnabled = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadMediaFiles();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _pin = prefs.getString('pin');
      _isBiometricAuthEnabled = prefs.getBool('biometric_auth') ?? false;
    });
  }

  Future<void> _loadMediaFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync();
    setState(() {
      _mediaFiles = files.where((file) => file is File).map((file) => file as File).toList();
    });
  }

  Future<void> _captureMedia(ImageSource source, {bool isVideo = false}) async {
    final pickedFile = isVideo
        ? await _picker.pickVideo(source: source)
        : await _picker.pickImage(source: source);

    if (pickedFile != null) {
      final encryptedFile = await _encryptFile(File(pickedFile.path));
      setState(() {
        _mediaFiles.add(encryptedFile);
      });
    }
  }

  Future<File> _encryptFile(File file) async {
    final key = encrypt.Key.fromUtf8('my 32 length key................');
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final bytes = await file.readAsBytes();
    final encrypted = encrypter.encryptBytes(bytes, iv: iv);

    final dir = await getApplicationDocumentsDirectory();
    final newFile = File('${dir.path}/${file.uri.pathSegments.last}.enc');
    await newFile.writeAsBytes(encrypted.bytes);

    await file.delete(); // Delete the original file for privacy

    return newFile;
  }

  Future<File?> _decryptFile(File file) async {
    try {
      final key = encrypt.Key.fromUtf8('my 32 length key................');
      final iv = encrypt.IV.fromLength(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      final bytes = await file.readAsBytes();
      final decrypted = encrypter.decryptBytes(encrypt.Encrypted(bytes), iv: iv);

      final dir = await getApplicationDocumentsDirectory();
      final newFilePath = '${dir.path}/${file.uri.pathSegments.last.replaceAll('.enc', '')}';

      if (file.path.toLowerCase().endsWith('.mp4.enc')) {
        // Return video file path directly
        return File(newFilePath);
      } else {
        // Return decrypted image file
        final newFile = File(newFilePath);
        await newFile.writeAsBytes(decrypted);
        return newFile;
      }
    } catch (e) {
      print('Error decrypting file: $e');
      return null; // Return null in case of any error
    }
  }





  Future<void> _setPIN(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pin', pin);
    setState(() {
      _pin = pin;
    });
  }

  Future<void> _toggleBiometricAuth(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_auth', enabled);
    setState(() {
      _isBiometricAuthEnabled = enabled;
    });
  }

  void _showSetPINDialog() {
    final _pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set PIN'),
        content: TextField(
          controller: _pinController,
          decoration: InputDecoration(hintText: 'Enter PIN'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _setPIN(_pinController.text);
              Navigator.of(context).pop();
            },
            child: Text('Set'),
          ),
        ],
      ),
    );
  }

  void _toggleLock() async {
    if (_isLocked) {
      bool isAuthenticated = false;

      if (_isBiometricAuthEnabled) {
        isAuthenticated = await _authenticateWithBiometrics();
      } else {
        isAuthenticated = await _authenticateWithPIN();
      }

      if (isAuthenticated) {
        setState(() {
          _isLocked = false;
        });
      }
    } else {
      setState(() {
        _isLocked = true;
      });
    }
  }

  Future<bool> _authenticateWithBiometrics() async {
    bool isAuthenticated = false;
    try {
      isAuthenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate to unlock your secure media',
      );
    } catch (e) {
      print('Error using biometric authentication: $e');
      // Handle error, show an error message or retry authentication
    }
    return isAuthenticated;
  }

  Future<bool> _authenticateWithPIN() async {
    bool isAuthenticated = false;
    final prefs = await SharedPreferences.getInstance();
    final storedPIN = prefs.getString('pin');

    if (storedPIN != null) {
      final result = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Enter PIN'),
          content: TextField(
            decoration: InputDecoration(hintText: 'Enter your PIN'),
            keyboardType: TextInputType.number,
            obscureText: true,
            onChanged: (value) {
              if (value == storedPIN) {
                Navigator.pop(context, true);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: Text('Cancel'),
            ),
          ],
        ),
      );
      isAuthenticated = result ?? false;
    }

    return isAuthenticated;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Secure Media'),
        actions: [
          IconButton(
            icon: Icon(Icons.lock),
            onPressed: _toggleLock,
          ),
        ],
      ),
      body: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
        itemCount: _mediaFiles.length,
        itemBuilder: (context, index) {
          final file = _mediaFiles[index];
          return GestureDetector(
            onTap: () {
              if (!_isLocked) {
                if (file.path.toLowerCase().endsWith('.mp4')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => VideoPlayerScreen(videoFile: file)),
                  );
                } else {
                  // Handle opening image in full screen
                }
              }
            },
            child: FutureBuilder<File?>(
              future: _decryptFile(file),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                } else if (snapshot.connectionState == ConnectionState.done) {
                  if (snapshot.hasError || snapshot.data == null) {
                    return Center(child: Text('Error loading media'));
                  }

                  final mediaFile = snapshot.data!;
                  if (mediaFile.path.toLowerCase().endsWith('.mp4')) {
                    return VideoPlayerThumbnail(videoFile: mediaFile);
                  } else {
                    return Image.file(mediaFile);
                  }
                } else {
                  return Center(child: Text('Loading...'));
                }
              },
            ),
          );
        },
      ),

      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            child: Icon(Icons.add_photo_alternate),
            onPressed: () {
              _captureMedia(ImageSource.gallery); // Change to ImageSource.gallery for gallery picker
            },
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            child: Icon(Icons.videocam),
            onPressed: () {
              _captureMedia(ImageSource.gallery, isVideo: true); // Change to ImageSource.gallery for gallery picker
            },
          ),
        ],
      ),
    );
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final File videoFile;

  const VideoPlayerScreen({Key? key, required this.videoFile}) : super(key: key);

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Video Player')),
      body: _controller.value.isInitialized
          ? AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: VideoPlayer(_controller),
      )
          : Center(child: CircularProgressIndicator()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class VideoPlayerThumbnail extends StatefulWidget {
  final File videoFile;

  const VideoPlayerThumbnail({Key? key, required this.videoFile}) : super(key: key);

  @override
  _VideoPlayerThumbnailState createState() => _VideoPlayerThumbnailState();
}

class _VideoPlayerThumbnailState extends State<VideoPlayerThumbnail> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black26,
            child: Icon(Icons.play_arrow, size: 50, color: Colors.white),
          ),
        ),
      ],
    )
        : Center(child: CircularProgressIndicator());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
