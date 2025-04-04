import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signalr_core/signalr_core.dart' hide ConnectionState;
import 'package:sizer/sizer.dart';
import '../Api/constants.dart';
import '../helper/Chat.dart';
import '../helper/token.dart';
import 'doctors.dart';

class MessagePage extends StatefulWidget {
  MessagePage({
    super.key,
    required this.idDoctor,
    required this.userName,
  });
  String? idDoctor;
  String? userName;

  @override
  _MessagePageState createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> {
  late String idDoctor;
  String? userId = "";
  late Chat chatService;
  bool isLoading = true;
  HubConnection? hubConnection;

  final TextEditingController messageController = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  XFile? imageFile;
  String? _filePath;

  final ScrollController scrollController = ScrollController();

  void fetchUserId() async {
    try {
      final fetchedUserId =
          await Tokens.getId(await Tokens.retrieve('access_token'));

      if (!mounted) return;

      // final fetchedUserName =
      //     await Tokens.getName(await Tokens.retrieve('access_token'));

      setState(() {
        userId = fetchedUserId;
        // userName = fetchedUserName;
      });
      print("UserId: $userId");
      //print("UserName: $userName");
    } catch (e) {
      print("Error fetching userId or userName: $e");
    }
  }

  void checkConnectionStatus() async {
    if (chatService.hubConnection?.state != HubConnectionState.connected) {
      try {
        await chatService.hubConnection?.start();
        print("Reconnecting...");
      } catch (e) {
        print("Error reconnecting: $e");
      }
    } else {
      print("Already connected.");
    }
  }

  bool isChatServiceInitialized() {
    return chatService.hubConnection?.state == HubConnectionState.connected;
  }

  void initializeChat() async {
    chatService = Chat();
    await chatService
        .openCon(await Tokens.getId(await Tokens.retrieve('access_token')));
    await chatService.startCon();
    listenMessage();
    initSignalR();
    initSignalRImage();
    print("Connection successful");

    if (chatService.hubConnection?.state != HubConnectionState.connected) {
      print("Connection failed to initialize properly.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Chat service not initialized or connection not established")),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    idDoctor = widget.idDoctor.toString();
    fetchUserId();
    initializeChat();
    fetchChatHistory();
  }

  void listenMessage() {
    chatService.hubConnection!.on("receiveMessage", (dynamic message) {
      if (message != null) {
              if (!mounted) return;

        print(" Received message: $message");

        // setState(() {
        //   messages.add({
        //     'text': message[0]['type'] == 'text' ? message[0]['content'] : null,
        //     'isReceived': message[0]['senderId'] != userId,
        //     'type': message[0]['type'],
        //     'image': message[0]['type'] == 'image'
        //         ? XFile("$resourceUrl${message[0]['content']}")
        //         : null,
        //   });
        // });
        setState(() {
          messages.add({
            'text': message[0]['type'] == 'text' ? message[0]['content'] : null,
            'isReceived': message[0]['senderId'] != userId,
            'type': message[0]['type'],
            'imageUrl': message[0]['type'] == 'image'
                ? "$resourceUrl${message[0]['content']}"
                : null,
          });
        });
        print("Received image path: ${message[0]['content']}");
        print(" Message added to state: ${message[0]['content']}");
        scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    messageController.dispose();
    scrollController.dispose();

    super.dispose();
  }

  Future<void> fetchChatHistory() async {
    setState(() {
      isLoading = true;
    });
    String senderId = await Tokens.getId(await Tokens.retrieve('access_token'));
    try {
      final chatHistory =
          await chatService.fetchChatHistory(senderId, idDoctor);
      print('chathistoryyyyy : $chatHistory');
      setState(() {
        messages = chatHistory
            .map((msg) => {
                  'text': msg['type'] == 'text' ? msg['content'] : null,
                  'isReceived': msg['senderId'] != userId,
                  'type': msg['type'],
                  'imageUrl': msg['type'] == 'image'
                      ? "$resourceUrl${msg['fileUrl']}"
                      : null,
                })
            .toList();
        isLoading = false;
        scrollToBottom();
        print("Loaded chat history: $chatHistory");
        chatHistory.forEach((msg) {
          if (msg['type'] == 'image') {
            print("Image URL from history: $resourceUrl${msg['fileUrl']}");
          }
        });
      });
    } catch (e) {
      print("Error fetching chat history: $e");

      setState(() {
        isLoading = false;
      });
    }
    print(fetchChatHistory);
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void sendImageToServer(XFile image) async {
    if (isChatServiceInitialized()) {
      try {
        String? data = await chatService.sendImage(idDoctor, image);

        if (data != "" && data != null) {
          String fileUrl = data;

          setState(() {
            messages.add({
              "senderId": userId,
              "receiverId": idDoctor,
              "type": "image",
              "imageUrl": "$resourceUrl$fileUrl",
              "isReceived": false,
            });
          });

          print("Image sent successfully: $resourceUrl$fileUrl");
          scrollToBottom();
        } else {
          print("Failed to receive file URL from server.");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to upload image, try again.")),
          );
        }
      } catch (e) {
        print("Error sending image: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send image: $e")),
        );
      }
    } else {
      print("Chat service not initialized or connection not established");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chat service not connected.")),
      );
    }
  }

  void sendMessageToServer(String text) async {
    if (isChatServiceInitialized()) {
      scrollToBottom();
      await chatService.sendMessage(idDoctor, text);
      messageController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Chat service not initialized or connection not established"),
        ),
      );
    }
  }

  void _pickImageFromGallery() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile =
          await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        print('Image picked: ${pickedFile.path}');
        sendImageToServer(pickedFile);
      } else {
        print('No image selected');
      }
    } catch (e) {
      print("Error picking image: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking image: $e")),
      );
    }
  }

  Future<void> initSignalRImage() async {
    try {
      hubConnection = HubConnectionBuilder()
          .withUrl(
              "$resourceUrl/chatHub?uid=${await Tokens.getId(await Tokens.retrieve('access_token'))}")
          .build();

      await hubConnection!.start();
      print("SignalR connection started for images.");

      hubConnection!.on("receiveFile", (dynamic data) async {
        if (data != null && data.isNotEmpty) {
          String fileUrl = data[0]["fileUrl"] ?? "";
          if (fileUrl.isNotEmpty) {
            setState(() {
              messages.add({
                "imageUrl": "$resourceUrl$fileUrl",
                "isReceived": true,
                "type": "image",
              });
            });
            scrollToBottom();
          }
        }
      });
    } catch (e) {
      print("Error initializing SignalR for images: $e");
    }
  }

  Future<void> initSignalR() async {
    try {
      hubConnection = HubConnectionBuilder()
          .withUrl(
              "$resourceUrl/chatHub?uid=${await Tokens.getId((await Tokens.retrieve('access_token')))}")
          .build();

      hubConnection!.onclose((error) {
        print("SignalR connection closed: $error");
      });

      hubConnection!.on("receiveMessage", (dynamic message) {
        print("Received message inside initSignalR: $message");
        try {
          if (message != null) {
            setState(() {
              messages.add({
                'text':
                    message[0]['type'] == 'text' ? message[0]['content'] : null,
                'isReceived': message[0]['senderId'] != userId,
                'type': message[0]['type'],
                'image': message[0]['type'] == 'image'
                    ? XFile(message[0]['content'])
                    : null,
              });
            });

            print("Message successfully added to chat list.");
            scrollToBottom();
          }
        } catch (e) {
          print("Error in message processing: $e");
        }
      });

      await hubConnection!.start();
      print("SignalR connection started successfully.");
    } catch (e) {
      print("Error initializing SignalR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: const AssetImage('Images/user.png'),
              radius: 4.5.w,
            ),
            SizedBox(width: 3.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.userName ?? ""}',
                  style: TextStyle(
                    fontSize: 20.sp,
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
        leading: Padding(
          padding: EdgeInsets.only(left: 4.w),
          child: IconButton(
            icon: Icon(
              Icons.arrow_circle_left_outlined,
              size: 22.3.sp,
              color: const Color(0xFF34539D),
            ),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: PrimaryColor))
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    padding: EdgeInsets.all(2.h),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      if (message['type'] == 'image') {
                        return Align(
                          alignment: message['isReceived']
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          child: Container(
                            margin: EdgeInsets.symmetric(
                                vertical: 5, horizontal: 10),
                            padding: EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: message['isReceived']
                                  ? Colors.blue[100]
                                  : Colors.green[100],
                            ),
                            child: Image.network(
                              message['imageUrl'] ?? "",
                              width: 200,
                              height: 200,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(Icons.broken_image,
                                      size: 100, color: Colors.red),
                            ),
                          ),
                        );
                      } else if (message['type'] == 'text') {
                        return buildMessage(
                            message['text'], message['isReceived']);
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(1.h),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.photo,
                          color: PrimaryColor,
                        ),
                        iconSize: 7.w,
                        onPressed: _pickImageFromGallery,
                      ),
                      Expanded(
                        child: TextField(
                          controller: messageController,
                          decoration: InputDecoration(
                            hintText: 'Send Message...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(3.w),
                            ),
                          ),
                          onSubmitted: (value) {
                            if (value.isNotEmpty) {
                              sendMessageToServer(value);
                            }
                          },
                        ),
                      ),
                      SizedBox(width: 2.h),
                      IconButton(
                        icon: const Icon(
                          Icons.send,
                          color: PrimaryColor,
                        ),
                        iconSize: 7.w,
                        onPressed: () {
                          final text = messageController.text;
                          if (text.isNotEmpty) {
                            sendMessageToServer(text);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget buildMessage(String message, bool isReceived) {
    return Align(
      alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        padding: EdgeInsets.all(2.h),
        margin: EdgeInsets.symmetric(vertical: 1.h),
        decoration: BoxDecoration(
          color: isReceived ? Colors.lightBlue[100] : Colors.green[100],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message,
          style: TextStyle(fontSize: 16.sp),
        ),
      ),
    );
  }

//################################################
  // void showFullImage(BuildContext context, XFile image) {
  //   showDialog(
  //     context: context,
  //     builder: (BuildContext context) {
  //       return Dialog(
  //         child: GestureDetector(
  //           onTap: () {
  //             Navigator.of(context).pop();
  //           },
  //           child: InteractiveViewer(
  //             child: Image.file(
  //               File(image.path),
  //               fit: BoxFit.contain,
  //             ),
  //           ),
  //         ),
  //       );
  //     },
  //   );
  // }
//################################################

  // Widget buildImageMessage(XFile image, bool isReceived) {
  //   return Align(
  //     alignment: isReceived ? Alignment.centerLeft : Alignment.centerRight,
  //     child: GestureDetector(
  //       onTap: () {
  //         showFullImage(context, image);
  //       },
  //       child: Container(
  //         margin: EdgeInsets.symmetric(vertical: 1.h),
  //         decoration: BoxDecoration(
  //           borderRadius: BorderRadius.circular(10),
  //         ),
  //         child: ClipRRect(
  //           borderRadius: BorderRadius.circular(10),
  //           child: Image.file(
  //             File(image.path),
  //             width: 40.w,
  //             height: 40.w,
  //             fit: BoxFit.cover,
  //           ),
  //         ),
  //       ),
  //     ),
  //   );
  // }
}
