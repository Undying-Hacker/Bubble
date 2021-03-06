import 'package:bubble/core/failures/failure.dart';
import 'package:bubble/core/params/params.dart';
import 'package:bubble/domain/entities/user.dart';
import 'package:bubble/domain/i_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: IAuth)
class AuthService implements IAuth {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final Firestore _store;

  AuthService(this._firebaseAuth, this._googleSignIn, this._store);

  @override
  Future<Either<AuthFailure, User>> getSignedInUser(Params _) async {
    final userOrNull = await _firebaseAuth.currentUser();
    return userOrNull != null
        ? Right((await _syncedUser(userOrNull)).toUser())
        : Left(AuthFailure("No authenticated user"));
  }

  Future<FirebaseUser> getFirebaseUser() async {
    return _firebaseAuth.currentUser();
  }

  @override
  Future<Either<AuthFailure, User>> signInWithEmailAndPassword(
      Params params) async {
    try {
      final inputData = params as ParamsCredentials;

      final authResult = await _firebaseAuth.signInWithEmailAndPassword(
          email: inputData.email, password: inputData.password);
      return Right(authResult.user.toUser());
    } on PlatformException catch (e) {
      return Left(AuthFailure(e.message));
    }
  }

  @override
  Future<Either<AuthFailure, User>> signInWithGoogle(Params _) async {
    AuthCredential credential;
    try {
      final googleUser = await _googleSignIn.signIn();
      final googleAuth = await googleUser.authentication;

      credential = GoogleAuthProvider.getCredential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final authResult = await _firebaseAuth.signInWithCredential(credential);
      final createdUser = authResult.user;
      final userRecord =
          await _store.collection("users").document(createdUser.uid).get();
      if (!userRecord.exists) {
        await _uploadUserDetails(createdUser.toDetails(), createdUser);
      }
      return Right(createdUser.toUser());
    } on PlatformException catch (e) {
      return Left(AuthFailure(e.message));
    } on Exception {
      return Left(AuthFailure("An unexpected error occurred"));
    }
  }

  @override
  Future<void> signOut(Params _) async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  @override
  Future<Either<AuthFailure, User>> signUpWithEmailAndPassword(
      Params params) async {
    try {
      //Cast to appropriate type
      final inputData = params as ParamsCredentials;

      final authResult = await _firebaseAuth.createUserWithEmailAndPassword(
          email: inputData.email, password: inputData.password);
      final createdUser = authResult.user;
      await _updateUserDetails(
          inputData.details["name"] as String, createdUser);
      await _uploadUserDetails(inputData.details, createdUser);
      return Right((await _firebaseAuth.currentUser()).toUser());
    } on PlatformException catch (e) {
      return Left(AuthFailure(e.message));
    }
  }

  Future<void> _uploadUserDetails(
      Map<String, dynamic> userDetails, FirebaseUser createdUser) {
    userDetails.addAll({
      "uid": createdUser.uid,
      "imageUrl":
          "https://firebasestorage.googleapis.com/v0/b/bubble-dd7c6.appspot.com/o/default_user.png?alt=media&token=b85948cb-9f71-46d9-a057-d37eaa6692e4",
      "state": "online",
      "lastActive": DateTime.now().millisecondsSinceEpoch.toString(),
      "token": "",
      "joinedRooms": []
    });
    return _store
        .collection("users")
        .document(createdUser.uid)
        .setData(userDetails);
  }

  Future<void> _updateUserDetails(String name, FirebaseUser createdUser) async {
    final userUpdateInfo = UserUpdateInfo();
    userUpdateInfo.photoUrl =
        "https://firebasestorage.googleapis.com/v0/b/bubble-dd7c6.appspot.com/o/default_user.png?alt=media&token=b85948cb-9f71-46d9-a057-d37eaa6692e4";
    userUpdateInfo.displayName = name;
    await createdUser.updateProfile(userUpdateInfo);
    await createdUser.reload();
  }

  Future<FirebaseUser> _syncedUser(FirebaseUser currentUser) async {
    final databaseUser =
        await _store.collection("users").document(currentUser.uid).get();
    if (databaseUser.data["imageUrl"] != currentUser.photoUrl) {
      await currentUser.updateProfile(
          UserUpdateInfo()..photoUrl = databaseUser.data["imageUrl"] as String);
      await currentUser.reload();
    }
    return _firebaseAuth.currentUser();
  }
}
