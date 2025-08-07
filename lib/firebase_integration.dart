import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

Future<String> uploadImage(String imagePath) async {
  try {
    final storageRef = FirebaseStorage.instance.ref().child('droplet_images/${DateTime.now().toIso8601String()}.jpg');
    await storageRef.putFile(File(imagePath));
    return await storageRef.getDownloadURL();
  } catch (e) {
    throw Exception('Failed to upload image: $e');
  }
}

Future<void> saveMeasurement(String imageUrl, double left, double right, double average) async {
  try {
    await FirebaseFirestore.instance.collection('measurements').add({
      'left_contact_angle': left,
      'right_contact_angle': right,
      'average_contact_angle': average,
      'image_url': imageUrl,
      'timestamp': Timestamp.now(),
    });
  } catch (e) {
    throw Exception('Failed to save measurement: $e');
  }
}