import 'dart:convert';

import 'package:ballys_reservation_app/utils/device_id.dart';
import 'package:ballys_reservation_app/utils/storage_util.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../services/api_service.dart';
import '../../models/user_model.dart';

class AuthRepository {
  final ApiService apiService;
  final FlutterSecureStorage storage;

  AuthRepository(this.apiService, this.storage);

  Future<String> authenticate() async {
    
    try {
       await storage.delete(key: 'access_token');
      final response = await apiService.post('Login', {
        "UserName": "BaLlY\$#Crm619",
        "PassWord": "cRm_0987_@bL",
      });

      if (response['Token'] != null &&
          response['Token']['access_token'] != null) {
        String accessToken = response['Token']['access_token'];
     print('accessToken $accessToken');
        await storage.write(key: 'access_token', value: accessToken);
       
        return accessToken;
      } else {
        throw Exception('Authentication failed: No token received');
      }
    } catch (e) {
     
      await storage.deleteAll();
      return "";
    }
  }

  Future<User> login(String text1, String text2) async {
    final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
    final deviceId = await DeviceId.get();
      final spName = await StorageUtil.getStoredProcedureName();
  print(deviceId);
  print(spName);
    final response = await apiService.post('CommonExecute', {
      "HasReturnData": "T",
      "Parameters": [
        {
          "Para_Data": 90144,
          "Para_Direction": "Input",
          "Para_Lenth": 1,
          "Para_Name": "@Iid",
          "Para_Type": "int",
        },
        {
          "Para_Data": text1,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text1",
          "Para_Type": "varchar",
        },
        {
          "Para_Data": text2,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text2",
          "Para_Type": "varchar",
        },
        {
          "Para_Data": deviceId,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text3",
          "Para_Type": "varchar",
        },
        {
          "Para_Data": "APP",
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text4",
          "Para_Type": "varchar",
        },
          {
          "Para_Data": currentVersion,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text29",
          "Para_Type": "varchar",
        },

      ],
      "SpName": spName,
      "con": "1",
    });
print("hellooo");
   print(response);

    if (response['CommonResult'] != null &&
        response['CommonResult']['Table'] is List &&
        response['CommonResult']['Table'].isNotEmpty) {
      final tableData = response['CommonResult']['Table'][0];

      if (tableData['LoginStatus'] == 'True') {
        return User(
          userName: tableData['Login_By'],
          uName: tableData['U_Name'],
          userLevel: tableData['User_Level'].toString(),
          salesCode: tableData['Sales_Code'].toString(),
          marketingCode: tableData['Marketing_Code'].toString(),
          // Ballys sends Coordinatorid when the user is a coordinator; it is
          // what the coordinator-request list is fetched by.
          coordinatorId: User.parseCoordinatorId(tableData),
          mobileNumber: tableData['Mobile'].toString(),
          memProfSH: tableData['Mem_Prof_SH'],
          giftApp: tableData['Gift_App'],
          resApp: tableData['R_App'],
          resChk: tableData['R_Chk'],
          otgiApp: tableData['G_App'],
          otgiChk: tableData['G_CHK'],
          bgApp: tableData['BG_APP'],
          bgChk: tableData['BG_CHK'],
          marketingP: User.parseMarketingP(tableData),
        );
      } else {
        // Handle login failure cases
        final loginId = tableData['LoginID'];
        if (loginId != null && loginId.toString().isNotEmpty) {
          throw Exception(loginId); // Throws "Your account deleted" or other error message
        } else {
          throw Exception('Login failed: Invalid credentials');
        }
      }
    } else {
      throw Exception('Login failed: unexpected response structure');
    }
  }

  /// Iid 646 — asks the server whether this user's access is unrestricted.
  ///
  /// [code] is how the server identifies the user: AD001 is looked up by its
  /// sales code, every other user by their marketing code (see
  /// [StorageUtil.getAccessCheckCode]). A "True" ReturnSatetus means screens
  /// that gate on the marketing group should let the user through.
  Future<bool> fetchAccessStatus(String code, String userName) async {
    try {
      final deviceId = await DeviceId.get();
      final spName = await StorageUtil.getStoredProcedureName();
      final response = await apiService.post('CommonExecute', {
        "HasReturnData": "T",
        "Parameters": [
          {
            "Para_Data": 646,
            "Para_Direction": "Input",
            "Para_Lenth": 1,
            "Para_Name": "@Iid",
            "Para_Type": "int",
          },
          {
            "Para_Data": code,
            "Para_Direction": "Input",
            "Para_Lenth": 100,
            "Para_Name": "@Text1",
            "Para_Type": "varchar",
          },
          {
            "Para_Data": userName,
            "Para_Direction": "Input",
            "Para_Lenth": 100,
            "Para_Name": "@Text2",
            "Para_Type": "varchar",
          },
          {
            "Para_Data": deviceId,
            "Para_Direction": "Input",
            "Para_Lenth": 100,
            "Para_Name": "@Text30",
            "Para_Type": "varchar",
          },
        ],
        "SpName": spName,
        "con": "1",
      });

      print("Access status response: $response");

      if (response['CommonResult'] != null &&
          response['CommonResult']['Table'] is List &&
          response['CommonResult']['Table'].isNotEmpty) {
        final tableData = response['CommonResult']['Table'][0];
        return tableData['ReturnSatetus'].toString().trim().toLowerCase() ==
            'true';
      }

      return false;
    } catch (e) {
      print("Access status error: $e");
      return false;
    }
  }

  // Add this method to auth_repository.dart

// Future<bool> deleteAccount() async {
//   try {
//     final deviceId = await DeviceId.get();
//      final username = await StorageUtil.getUserName();
//      print( 'username delete account: $username');
//     final response = await apiService.post('CommonExecute', {
//       "HasReturnData": "T",
//       "Parameters": [
//         {
//           "Para_Data": 90145,
//           "Para_Direction": "Input",
//           "Para_Lenth": 1,
//           "Para_Name": "@Iid",
//           "Para_Type": "int",
//         },
//           {
//           "Para_Data": username,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text1",
//           "Para_Type": "varchar",
//         },
//         {
//           "Para_Data": deviceId,
//           "Para_Direction": "Input",
//           "Para_Lenth": 100,
//           "Para_Name": "@Text30",
//           "Para_Type": "varchar",
//         }
//       ],
//       "SpName": "sp_CRM_Common_API",
//       "con": "1",
//     });

//     print("Delete account response: $response");

//     // Check if deletion was successful
//     if (response['CommonResult'] != null &&
//         response['CommonResult']['Table'] is List &&
//         response['CommonResult']['Table'].isNotEmpty) {
//       final tableData = response['CommonResult']['Table'][0];
      
     
//       return tableData['is_active'] == 'true' || tableData['DeleteStatus'] == 'Success';
//     }
    
//     return false;
//   } catch (e) {
//     print("Delete account error: $e");
//     throw Exception('Failed to delete account: ${e.toString()}');
//   }
// }
// In auth_repository.dart - Replace the deleteAccount method with this:

Future<bool> deleteAccount() async {
  try {
    final deviceId = await DeviceId.get();
    final username = await StorageUtil.getUserName();
    print('username delete account: $username');
     final spName = await StorageUtil.getStoredProcedureName();
    final response = await apiService.post('CommonExecute', {
      "HasReturnData": "T",
      "Parameters": [
        {
          "Para_Data": 90145,
          "Para_Direction": "Input",
          "Para_Lenth": 1,
          "Para_Name": "@Iid",
          "Para_Type": "int",
        },
        {
          "Para_Data": username,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text1",
          "Para_Type": "varchar",
        },
        {
          "Para_Data": deviceId,
          "Para_Direction": "Input",
          "Para_Lenth": 100,
          "Para_Name": "@Text30",
          "Para_Type": "varchar",
        }
      ],
      "SpName": spName,
      "con": "1",
    });

    print("Delete account response: $response");

    // Check if the response structure is valid
    if (response['CommonResult'] != null &&
        response['CommonResult']['Table'] is List &&
        response['CommonResult']['Table'].isNotEmpty) {
      final tableData = response['CommonResult']['Table'][0];
      
      print("Table data: $tableData");
      print("is_active value: ${tableData['is_active']}, type: ${tableData['is_active'].runtimeType}");
      
      // Based on your API response, is_active: true means deletion was successful
      // This seems counterintuitive but matches your API design
      if (tableData.containsKey('is_active')) {
        final isActive = tableData['is_active'];
        // Return true if is_active is true (indicating successful deletion)
        return isActive == true || isActive == 'true';
      }
      
      // Fallback check for DeleteStatus
      if (tableData.containsKey('DeleteStatus')) {
        return tableData['DeleteStatus'] == 'Success';
      }
      
      // If neither field exists but we got a response, consider it successful
      return true;
    }
    
    // If response structure is invalid, return false
    print("Invalid response structure");
    return false;
  } catch (e) {
    print("Delete account error: $e");
    // Return false instead of throwing to allow proper error handling
    return false;
  }
}
Future<bool> sendOtpWhatsApp(String mobileNumber, String otp) async {
  try {
    // await apiService.post('send-whatsapp', {
    //   "Mobile_No": mobileNumber,
    //   "OTP": otp,
    // });
    print("hello $mobileNumber");
const String url =
        'https://api.ballyscolombo.com/api/Ballys/CRM/send-whatsapp';

     final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "Mobile_No": mobileNumber,
        "OTP": otp,
      }),
    ).timeout(const Duration(seconds: 10));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (e) {
    print('WhatsApp OTP send error: $e');
    return false;
  }
}
}