import 'package:cloud_functions/cloud_functions.dart';

/// Claims intake QR codes through the `redeemQr` Cloud Function
/// (firebase/functions/src/index.ts). Points are computed and written
/// server-side; Firestore rules don't let clients write them.
class QRService {
  QRService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Claims a QR code for the signed-in user.
  /// Returns `{pointsUser, co2Saved, totalWeight}`.
  /// Throws on error (e.g. already used, invalid qrId).
  Future<Map<String, dynamic>> scanQRCode(String qrId) async {
    try {
      final result =
          await _functions.httpsCallable('redeemQr').call({'qrId': qrId});
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' && e.message == 'NOT_FOUND') {
        // The function itself is missing, not the QR code.
        throw Exception('QR redemption is not set up on the server yet '
            '(deploy the Cloud Functions, see README Step 9).');
      }
      throw Exception(e.message ?? 'Could not claim this QR code.');
    }
  }
}
