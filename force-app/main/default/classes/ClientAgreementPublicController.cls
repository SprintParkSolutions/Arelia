// /**
//  * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
//  * Class Name      : ClientAgreementPublicController
//  * Author          : <YourName>
//  * Created Date    : Jun 10, 2026
//  * Last Modified By: <YourName>
//  * Last Modified On: Jun 10, 2026
//  * Description     : Public token/record-id based controller for client agreement viewing and signing.
//  * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
//  */
// public without sharing class ClientAgreementPublicController {

//     private static final String DEBUG_PREFIX = 'CLIENT_AGREEMENT_PUBLIC_DEBUG: ';

//     @AuraEnabled(cacheable=false)
//     public static ClientAgreementDTO.PublicAgreementResponse getAgreementByToken(String token) {
//         System.debug(DEBUG_PREFIX + 'getAgreementByToken START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Token received: ' + token);
//         System.debug(DEBUG_PREFIX + 'Token length: ' + (token == null ? 0 : token.length()));

//         ClientAgreementDTO.PublicAgreementResponse response =
//             new ClientAgreementDTO.PublicAgreementResponse();

//         if (String.isBlank(token)) {
//             System.debug(DEBUG_PREFIX + 'Token is blank. Returning invalid signing link.');
//             response.valid = false;
//             response.message = 'Invalid signing link.';
//             return response;
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Agreement_HTML__c,
//                    Token__c,
//                    Token_Expiry__c,
//                    Opportunity__c,
//                    Opportunity__r.Email__c,
//                    Opportunity__r.Supervisor_User_Email__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Token__c = :token
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by token: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             response.valid = false;
//             response.message = 'Invalid or expired signing link.';
//             return response;
//         }

//         Client_Agreement__c agreement = agreements[0];

//         System.debug(DEBUG_PREFIX + 'Agreement Id: ' + agreement.Id);
//         System.debug(DEBUG_PREFIX + 'Agreement Status: ' + agreement.Status__c);
//         System.debug(DEBUG_PREFIX + 'Agreement Token Expiry: ' + agreement.Token_Expiry__c);
//         System.debug(DEBUG_PREFIX + 'Opportunity Id: ' + agreement.Opportunity__c);
//         System.debug(DEBUG_PREFIX + 'Opportunity RecordTypeId: ' + agreement.Opportunity__r.RecordTypeId);

//         try {
//             validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
//             System.debug(DEBUG_PREFIX + 'Arelia validation successful.');
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Arelia validation failed: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + 'Arelia validation stack: ' + e.getStackTraceString());
//             response.valid = false;
//             response.message = 'Invalid agreement.';
//             return response;
//         }

//         if (agreement.Status__c == 'Signed') {
//             System.debug(DEBUG_PREFIX + 'Agreement already signed.');
//             response.valid = false;
//             response.message = 'This agreement has already been signed.';
//             return response;
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             System.debug(DEBUG_PREFIX + 'Agreement expired. Attempting to update Status__c = Expired.');

//             agreement.Status__c = 'Expired';

//             try {
//                 update agreement;
//                 System.debug(DEBUG_PREFIX + 'Expired status update successful.');
//             } catch (Exception e) {
//                 System.debug(DEBUG_PREFIX + 'Expired status update failed: ' + e.getMessage());
//                 System.debug(DEBUG_PREFIX + 'Expired status update stack: ' + e.getStackTraceString());
//                 throw new AuraHandledException(e.getMessage());
//             }

//             response.valid = false;
//             response.message = 'This signing link has expired.';
//             return response;
//         }

//         response.valid = true;
//         response.message = 'Success';
//         response.agreementId = agreement.Id;
//         response.agreementHtml = agreement.Agreement_HTML__c;
//         response.clientEmail = agreement.Opportunity__r.Email__c;
//         response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
//         response.status = agreement.Status__c;

//         response.supportingFiles =
//             ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
//                 agreement.Opportunity__c,
//                 agreement.Id
//             );

//         System.debug(DEBUG_PREFIX + 'getAgreementByToken END - Success');
//         return response;
//     }

//     @AuraEnabled
//     public static void submitSignature(
//         Id agreementId,
//         String signatureBase64,
//         String signedAgreementHtml,
//         String signedPdfBase64
//     ) {
//         System.debug(DEBUG_PREFIX + 'submitSignature START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Name: ' + UserInfo.getName());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);
//         System.debug(DEBUG_PREFIX + 'Signature Base64 length: ' + (signatureBase64 == null ? 0 : signatureBase64.length()));
//         System.debug(DEBUG_PREFIX + 'Signed Agreement HTML length: ' + (signedAgreementHtml == null ? 0 : signedAgreementHtml.length()));
//         System.debug(DEBUG_PREFIX + 'Signed PDF Base64 length: ' + (signedPdfBase64 == null ? 0 : signedPdfBase64.length()));

//         if (agreementId == null) {
//             System.debug(DEBUG_PREFIX + 'Agreement Id is null.');
//             throw new AuraHandledException('Invalid agreement link.');
//         }

//         if (String.isBlank(signatureBase64)) {
//             System.debug(DEBUG_PREFIX + 'Signature Base64 is blank.');
//             throw new AuraHandledException('Signature is required.');
//         }

//         if (String.isBlank(signedAgreementHtml)) {
//             System.debug(DEBUG_PREFIX + 'Signed Agreement HTML is blank.');
//             throw new AuraHandledException('Signed agreement HTML is required.');
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Agreement_HTML__c,
//                    Token__c,
//                    Token_Expiry__c,
//                    Opportunity__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Id = :agreementId
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by Id: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             System.debug(DEBUG_PREFIX + 'No Client Agreement found for Id: ' + agreementId);
//             throw new AuraHandledException('Invalid agreement link.');
//         }

//         Client_Agreement__c agreement = agreements[0];

//         System.debug(DEBUG_PREFIX + 'Agreement before update - Id: ' + agreement.Id);
//         System.debug(DEBUG_PREFIX + 'Agreement before update - Status__c: ' + agreement.Status__c);
//         System.debug(DEBUG_PREFIX + 'Agreement before update - Token__c is blank: ' + String.isBlank(agreement.Token__c));
//         System.debug(DEBUG_PREFIX + 'Agreement before update - Token_Expiry__c: ' + agreement.Token_Expiry__c);
//         System.debug(DEBUG_PREFIX + 'Agreement before update - Opportunity__c: ' + agreement.Opportunity__c);
//         System.debug(DEBUG_PREFIX + 'Agreement before update - Opportunity RecordTypeId: ' + agreement.Opportunity__r.RecordTypeId);

//         try {
//             validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
//             System.debug(DEBUG_PREFIX + 'Arelia validation successful in submitSignature.');
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Arelia validation failed in submitSignature: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + 'Arelia validation stack in submitSignature: ' + e.getStackTraceString());
//             throw new AuraHandledException(e.getMessage());
//         }

//         if (agreement.Status__c == 'Signed') {
//             System.debug(DEBUG_PREFIX + 'Agreement already signed. Stopping submitSignature.');
//             throw new AuraHandledException('This agreement has already been signed.');
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             System.debug(DEBUG_PREFIX + 'Agreement expired during submitSignature. Attempting expiry update.');

//             agreement.Status__c = 'Expired';

//             try {
//                 update agreement;
//                 System.debug(DEBUG_PREFIX + 'Expired status update successful in submitSignature.');
//             } catch (Exception e) {
//                 System.debug(DEBUG_PREFIX + 'Expired status update failed in submitSignature: ' + e.getMessage());
//                 System.debug(DEBUG_PREFIX + 'Expired status update stack in submitSignature: ' + e.getStackTraceString());
//                 throw new AuraHandledException(e.getMessage());
//             }

//             throw new AuraHandledException('This signing link has expired.');
//         }

//         agreement.Signature_Base64__c = signatureBase64;
//         agreement.Signed_Date__c = System.now();
//         agreement.Agreement_HTML__c = signedAgreementHtml;
//         agreement.Status__c = 'Signed';
//         agreement.Token__c = null;

//         System.debug(DEBUG_PREFIX + 'Prepared agreement for update.');
//         System.debug(DEBUG_PREFIX + 'Prepared Status__c: ' + agreement.Status__c);
//         System.debug(DEBUG_PREFIX + 'Prepared Signed_Date__c: ' + agreement.Signed_Date__c);
//         System.debug(DEBUG_PREFIX + 'Prepared Token__c is blank: ' + String.isBlank(agreement.Token__c));

//         try {
//             System.debug(DEBUG_PREFIX + 'Attempting update agreement now.');
//             update agreement;
//             System.debug(DEBUG_PREFIX + 'Agreement update successful.');
//         } catch (DmlException e) {
//             System.debug(DEBUG_PREFIX + 'Agreement update failed with DmlException.');
//             System.debug(DEBUG_PREFIX + 'DML Message: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + 'DML Type: ' + e.getTypeName());
//             System.debug(DEBUG_PREFIX + 'DML Stack: ' + e.getStackTraceString());

//             for (Integer i = 0; i < e.getNumDml(); i++) {
//                 System.debug(DEBUG_PREFIX + 'DML index ' + i + ' message: ' + e.getDmlMessage(i));
//                 System.debug(DEBUG_PREFIX + 'DML index ' + i + ' status code: ' + e.getDmlStatusCode(i));
//                 System.debug(DEBUG_PREFIX + 'DML index ' + i + ' fields: ' + e.getDmlFields(i));
//             }

//             throw new AuraHandledException(e.getMessage());
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Agreement update failed with general Exception.');
//             System.debug(DEBUG_PREFIX + 'Exception Message: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + 'Exception Type: ' + e.getTypeName());
//             System.debug(DEBUG_PREFIX + 'Exception Stack: ' + e.getStackTraceString());

//             throw new AuraHandledException(e.getMessage());
//         }

//         if (!String.isBlank(signedPdfBase64)) {
//             System.debug(DEBUG_PREFIX + 'Signed PDF Base64 present. Enqueueing ClientAgreementSignedPdfJob.');

//             try {
//                 System.enqueueJob(new ClientAgreementSignedPdfJob(agreement.Id, signedPdfBase64));
//                 System.debug(DEBUG_PREFIX + 'ClientAgreementSignedPdfJob enqueued successfully.');
//             } catch (Exception e) {
//                 System.debug(DEBUG_PREFIX + 'Failed to enqueue ClientAgreementSignedPdfJob: ' + e.getMessage());
//                 System.debug(DEBUG_PREFIX + 'Queueable enqueue stack: ' + e.getStackTraceString());
//                 throw new AuraHandledException(e.getMessage());
//             }
//         } else {
//             System.debug(DEBUG_PREFIX + 'Signed PDF Base64 is blank. PDF job not enqueued.');
//         }

//         System.debug(DEBUG_PREFIX + 'submitSignature END - Success');
//     }

//     private static void validateAreliaOpportunity(Id opportunityRecordTypeId) {
//         System.debug(DEBUG_PREFIX + 'validateAreliaOpportunity START');
//         System.debug(DEBUG_PREFIX + 'Opportunity RecordTypeId received: ' + opportunityRecordTypeId);

//         if (opportunityRecordTypeId == null) {
//             System.debug(DEBUG_PREFIX + 'Opportunity RecordTypeId is null.');
//             throw new AuraHandledException('Opportunity Record Type is missing.');
//         }

//         Map<Id, Schema.RecordTypeInfo> recordTypeMap =
//             Schema.SObjectType.Opportunity.getRecordTypeInfosById();

//         Schema.RecordTypeInfo rtInfo = recordTypeMap.get(opportunityRecordTypeId);

//         System.debug(DEBUG_PREFIX + 'RecordTypeInfo found: ' + (rtInfo != null));

//         if (rtInfo != null) {
//             System.debug(DEBUG_PREFIX + 'RecordType DeveloperName: ' + rtInfo.getDeveloperName());
//             System.debug(DEBUG_PREFIX + 'RecordType Name: ' + rtInfo.getName());
//         }

//         if (rtInfo == null || rtInfo.getDeveloperName() != 'Arelia') {
//             System.debug(DEBUG_PREFIX + 'Invalid record type. Expected DeveloperName = Arelia.');
//             throw new AuraHandledException('Invalid agreement.');
//         }

//         System.debug(DEBUG_PREFIX + 'validateAreliaOpportunity END - Success');
//     }

//     @AuraEnabled(cacheable=false)
//     public static ClientAgreementDTO.PublicAgreementResponse getAgreementById(Id agreementId) {
//         System.debug(DEBUG_PREFIX + 'getAgreementById START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);

//         ClientAgreementDTO.PublicAgreementResponse response =
//             new ClientAgreementDTO.PublicAgreementResponse();

//         if (agreementId == null) {
//             System.debug(DEBUG_PREFIX + 'Agreement Id is null in getAgreementById.');
//             response.valid = false;
//             response.message = 'Invalid signing link.';
//             return response;
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Agreement_HTML__c,
//                    Token__c,
//                    Token_Expiry__c,
//                    Opportunity__c,
//                    Opportunity__r.Email__c,
//                    Opportunity__r.Supervisor_User_Email__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Id = :agreementId
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by Id in getAgreementById: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             response.valid = false;
//             response.message = 'Invalid or expired signing link.';
//             return response;
//         }

//         Client_Agreement__c agreement = agreements[0];

//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Id: ' + agreement.Id);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Status__c: ' + agreement.Status__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Token_Expiry__c: ' + agreement.Token_Expiry__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Opportunity__c: ' + agreement.Opportunity__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Opportunity RecordTypeId: ' + agreement.Opportunity__r.RecordTypeId);

//         try {
//             validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
//             System.debug(DEBUG_PREFIX + 'Arelia validation successful in getAgreementById.');
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Arelia validation failed in getAgreementById: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + 'Arelia validation stack in getAgreementById: ' + e.getStackTraceString());

//             response.valid = false;
//             response.message = 'Invalid agreement.';
//             return response;
//         }

//         if (agreement.Status__c == 'Signed') {
//             System.debug(DEBUG_PREFIX + 'Agreement already signed in getAgreementById.');
//             response.valid = false;
//             response.message = 'This agreement has already been signed.';
//             return response;
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             System.debug(DEBUG_PREFIX + 'Agreement expired in getAgreementById. Attempting expiry update.');

//             agreement.Status__c = 'Expired';

//             try {
//                 update agreement;
//                 System.debug(DEBUG_PREFIX + 'Expired status update successful in getAgreementById.');
//             } catch (Exception e) {
//                 System.debug(DEBUG_PREFIX + 'Expired status update failed in getAgreementById: ' + e.getMessage());
//                 System.debug(DEBUG_PREFIX + 'Expired status update stack in getAgreementById: ' + e.getStackTraceString());
//                 throw new AuraHandledException(e.getMessage());
//             }

//             response.valid = false;
//             response.message = 'This signing link has expired.';
//             return response;
//         }

//         response.valid = true;
//         response.message = 'Success';
//         response.agreementId = agreement.Id;
//         response.agreementHtml = agreement.Agreement_HTML__c;
//         response.clientEmail = agreement.Opportunity__r.Email__c;
//         response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
//         response.status = agreement.Status__c;

//         System.debug(DEBUG_PREFIX + 'Before loading supporting files.');

//         response.supportingFiles =
//             ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
//                 agreement.Opportunity__c,
//                 agreement.Id
//             );

//         System.debug(DEBUG_PREFIX + 'Supporting files loaded. Count: ' +
//             (response.supportingFiles == null ? 0 : response.supportingFiles.size()));

//         System.debug(DEBUG_PREFIX + 'getAgreementById END - Success');

//         return response;
//     }
// }

/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementPublicController
 * Author          : <YourName>
 * Created Date    : Jun 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 10, 2026
 * Description     : Public token/record-id based controller for client agreement viewing and signing.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
// public without sharing class ClientAgreementPublicController {

//     private static final String DEBUG_PREFIX = 'CLIENT_AGREEMENT_PUBLIC_DEBUG: ';

//     @AuraEnabled(cacheable=false)
//     public static ClientAgreementDTO.PublicAgreementResponse getAgreementByToken(String token) {
//         System.debug(DEBUG_PREFIX + 'getAgreementByToken START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Token received: ' + token);
//         System.debug(DEBUG_PREFIX + 'Token length: ' + (token == null ? 0 : token.length()));

//         ClientAgreementDTO.PublicAgreementResponse response =
//             new ClientAgreementDTO.PublicAgreementResponse();

//         if (String.isBlank(token)) {
//             response.valid = false;
//             response.message = 'Invalid signing link.';
//             return response;
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Agreement_HTML__c,
//                    Token__c,
//                    Token_Expiry__c,
//                    Opportunity__c,
//                    Opportunity__r.Email__c,
//                    Opportunity__r.Supervisor_User_Email__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Token__c = :token
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by token: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             response.valid = false;
//             response.message = 'Invalid or expired signing link.';
//             return response;
//         }

//         Client_Agreement__c agreement = agreements[0];

//         try {
//             validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Arelia validation failed: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + e.getStackTraceString());

//             response.valid = false;
//             response.message = 'Invalid agreement.';
//             return response;
//         }

//         if (agreement.Status__c == 'Signed') {
//             response.valid = false;
//             response.message = 'This agreement has already been signed.';
//             return response;
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             /*
//              * Do not update Client_Agreement__c here.
//              * This method is called by guest user.
//              */
//             response.valid = false;
//             response.message = 'This signing link has expired.';
//             return response;
//         }

//         response.valid = true;
//         response.message = 'Success';
//         response.agreementId = agreement.Id;
//         response.agreementHtml = agreement.Agreement_HTML__c;
//         response.clientEmail = agreement.Opportunity__r.Email__c;
//         response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
//         response.status = agreement.Status__c;

//         response.supportingFiles =
//             ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
//                 agreement.Opportunity__c,
//                 agreement.Id
//             );

//         System.debug(DEBUG_PREFIX + 'getAgreementByToken END - Success');
//         return response;
//     }

//     @AuraEnabled(cacheable=false)
//     public static ClientAgreementDTO.PublicAgreementResponse getAgreementById(Id agreementId) {
//         System.debug(DEBUG_PREFIX + 'getAgreementById START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);

//         ClientAgreementDTO.PublicAgreementResponse response =
//             new ClientAgreementDTO.PublicAgreementResponse();

//         if (agreementId == null) {
//             response.valid = false;
//             response.message = 'Invalid signing link.';
//             return response;
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Agreement_HTML__c,
//                    Token__c,
//                    Token_Expiry__c,
//                    Opportunity__c,
//                    Opportunity__r.Email__c,
//                    Opportunity__r.Supervisor_User_Email__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Id = :agreementId
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by Id in getAgreementById: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             response.valid = false;
//             response.message = 'Invalid or expired signing link.';
//             return response;
//         }

//         Client_Agreement__c agreement = agreements[0];

//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Id: ' + agreement.Id);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Status__c: ' + agreement.Status__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Token_Expiry__c: ' + agreement.Token_Expiry__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Opportunity__c: ' + agreement.Opportunity__c);
//         System.debug(DEBUG_PREFIX + 'Agreement loaded - Opportunity RecordTypeId: ' + agreement.Opportunity__r.RecordTypeId);

//         try {
//             validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
//             System.debug(DEBUG_PREFIX + 'Arelia validation successful in getAgreementById.');
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Arelia validation failed in getAgreementById: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + e.getStackTraceString());

//             response.valid = false;
//             response.message = 'Invalid agreement.';
//             return response;
//         }

//         if (agreement.Status__c == 'Signed') {
//             response.valid = false;
//             response.message = 'This agreement has already been signed.';
//             return response;
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             /*
//              * Do not update Client_Agreement__c here.
//              * This method is called by guest user.
//              */
//             response.valid = false;
//             response.message = 'This signing link has expired.';
//             return response;
//         }

//         response.valid = true;
//         response.message = 'Success';
//         response.agreementId = agreement.Id;
//         response.agreementHtml = agreement.Agreement_HTML__c;
//         response.clientEmail = agreement.Opportunity__r.Email__c;
//         response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
//         response.status = agreement.Status__c;

//         System.debug(DEBUG_PREFIX + 'Before loading supporting files.');

//         response.supportingFiles =
//             ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
//                 agreement.Opportunity__c,
//                 agreement.Id
//             );

//         System.debug(DEBUG_PREFIX + 'Supporting files loaded. Count: ' +
//             (response.supportingFiles == null ? 0 : response.supportingFiles.size()));

//         System.debug(DEBUG_PREFIX + 'getAgreementById END - Success');

//         return response;
//     }

//     @AuraEnabled
//     public static void submitSignature(
//         Id agreementId,
//         String signatureBase64,
//         String signedAgreementHtml,
//         String signedPdfBase64
//     ) {
//         System.debug(DEBUG_PREFIX + 'submitSignature START');
//         System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
//         System.debug(DEBUG_PREFIX + 'Running User Name: ' + UserInfo.getName());
//         System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
//         System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);
//         System.debug(DEBUG_PREFIX + 'Signature Base64 length: ' + getStringLength(signatureBase64));
//         System.debug(DEBUG_PREFIX + 'Signed Agreement HTML length: ' + getStringLength(signedAgreementHtml));
//         System.debug(DEBUG_PREFIX + 'Signed PDF Base64 length: ' + getStringLength(signedPdfBase64));

//         if (agreementId == null) {
//             throw new AuraHandledException('Invalid agreement link.');
//         }

//         if (String.isBlank(signatureBase64)) {
//             throw new AuraHandledException('Signature is required.');
//         }

//         if (String.isBlank(signedAgreementHtml)) {
//             throw new AuraHandledException('Signed agreement HTML is required.');
//         }

//         List<Client_Agreement__c> agreements = [
//             SELECT Id,
//                    Status__c,
//                    Token_Expiry__c,
//                    Opportunity__r.RecordTypeId
//             FROM Client_Agreement__c
//             WHERE Id = :agreementId
//             LIMIT 1
//         ];

//         System.debug(DEBUG_PREFIX + 'Agreements found by Id in submitSignature: ' + agreements.size());

//         if (agreements.isEmpty()) {
//             throw new AuraHandledException('Invalid agreement link.');
//         }

//         Client_Agreement__c agreement = agreements[0];

//         validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);

//         if (agreement.Status__c == 'Signed') {
//             throw new AuraHandledException('This agreement has already been signed.');
//         }

//         if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
//             /*
//              * Do not update Client_Agreement__c here.
//              * The public guest transaction should not perform UPDATE DML.
//              */
//             throw new AuraHandledException('This signing link has expired.');
//         }

//         try {
//             System.debug(DEBUG_PREFIX + 'Enqueueing ClientAgreementSignatureSubmitJob.');

//             System.enqueueJob(
//                 new ClientAgreementSignatureSubmitJob(
//                     agreementId,
//                     signatureBase64,
//                     signedAgreementHtml,
//                     signedPdfBase64
//                 )
//             );

//             System.debug(DEBUG_PREFIX + 'ClientAgreementSignatureSubmitJob enqueued successfully.');
//         } catch (Exception e) {
//             System.debug(DEBUG_PREFIX + 'Failed to enqueue ClientAgreementSignatureSubmitJob: ' + e.getMessage());
//             System.debug(DEBUG_PREFIX + e.getStackTraceString());

//             throw new AuraHandledException(e.getMessage());
//         }

//         System.debug(DEBUG_PREFIX + 'submitSignature END - Queueable submitted');
//     }

//     private static void validateAreliaOpportunity(Id opportunityRecordTypeId) {
//         System.debug(DEBUG_PREFIX + 'validateAreliaOpportunity START');
//         System.debug(DEBUG_PREFIX + 'Opportunity RecordTypeId received: ' + opportunityRecordTypeId);

//         if (opportunityRecordTypeId == null) {
//             throw new AuraHandledException('Opportunity Record Type is missing.');
//         }

//         Map<Id, Schema.RecordTypeInfo> recordTypeMap =
//             Schema.SObjectType.Opportunity.getRecordTypeInfosById();

//         Schema.RecordTypeInfo rtInfo = recordTypeMap.get(opportunityRecordTypeId);

//         if (rtInfo == null || rtInfo.getDeveloperName() != 'Arelia') {
//             throw new AuraHandledException('Invalid agreement.');
//         }

//         System.debug(DEBUG_PREFIX + 'validateAreliaOpportunity END - Success');
//     }

//     private static Integer getStringLength(String value) {
//         return value == null ? 0 : value.length();
//     }
// }

/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementPublicController
 * Description     : Public token/record-id based controller for client agreement viewing and signing.
 *                   Guest user does not update Client_Agreement__c directly.
 *                   Guest user creates Client_Agreement_Submission__c and publishes platform event.
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */
public without sharing class ClientAgreementPublicController {

    private static final String DEBUG_PREFIX = 'CLIENT_AGREEMENT_PUBLIC_DEBUG: ';
    private static final Integer PDF_CHUNK_SIZE = 100000;

    @AuraEnabled(cacheable=false)
    public static ClientAgreementDTO.PublicAgreementResponse getAgreementByToken(String token) {
        System.debug(DEBUG_PREFIX + 'getAgreementByToken START');

        ClientAgreementDTO.PublicAgreementResponse response =
            new ClientAgreementDTO.PublicAgreementResponse();

        if (String.isBlank(token)) {
            response.valid = false;
            response.message = 'Invalid signing link.';
            return response;
        }

        List<Client_Agreement__c> agreements = [
            SELECT Id,
                   Status__c,
                   Agreement_HTML__c,
                   Token__c,
                   Token_Expiry__c,
                   Opportunity__c,
                   Opportunity__r.Email__c,
                   Opportunity__r.Supervisor_User_Email__c,
                   Opportunity__r.RecordTypeId
            FROM Client_Agreement__c
            WHERE Token__c = :token
            LIMIT 1
        ];

        if (agreements.isEmpty()) {
            response.valid = false;
            response.message = 'Invalid or expired signing link.';
            return response;
        }

        Client_Agreement__c agreement = agreements[0];

        try {
            validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
        } catch (Exception e) {
            System.debug(DEBUG_PREFIX + 'Arelia validation failed: ' + e.getMessage());
            System.debug(DEBUG_PREFIX + e.getStackTraceString());

            response.valid = false;
            response.message = 'Invalid agreement.';
            return response;
        }

        if (agreement.Status__c == 'Signed') {
            response.valid = false;
            response.message = 'This agreement has already been signed.';
            return response;
        }

        if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
            response.valid = false;
            response.message = 'This signing link has expired.';
            return response;
        }

        response.valid = true;
        response.message = 'Success';
        response.agreementId = agreement.Id;
        response.agreementHtml = agreement.Agreement_HTML__c;
        response.clientEmail = agreement.Opportunity__r.Email__c;
        response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
        response.status = agreement.Status__c;

        response.supportingFiles =
            ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
                agreement.Opportunity__c,
                agreement.Id
            );

        System.debug(DEBUG_PREFIX + 'getAgreementByToken END - Success');
        return response;
    }

    @AuraEnabled(cacheable=false)
    public static ClientAgreementDTO.PublicAgreementResponse getAgreementById(Id agreementId) {
        System.debug(DEBUG_PREFIX + 'getAgreementById START');
        System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
        System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
        System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);

        ClientAgreementDTO.PublicAgreementResponse response =
            new ClientAgreementDTO.PublicAgreementResponse();

        if (agreementId == null) {
            response.valid = false;
            response.message = 'Invalid signing link.';
            return response;
        }

        List<Client_Agreement__c> agreements = [
            SELECT Id,
                   Status__c,
                   Agreement_HTML__c,
                   Token__c,
                   Token_Expiry__c,
                   Opportunity__c,
                   Opportunity__r.Email__c,
                   Opportunity__r.Supervisor_User_Email__c,
                   Opportunity__r.RecordTypeId
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        System.debug(DEBUG_PREFIX + 'Agreements found by Id in getAgreementById: ' + agreements.size());

        if (agreements.isEmpty()) {
            response.valid = false;
            response.message = 'Invalid or expired signing link.';
            return response;
        }

        Client_Agreement__c agreement = agreements[0];

        try {
            validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);
        } catch (Exception e) {
            System.debug(DEBUG_PREFIX + 'Arelia validation failed in getAgreementById: ' + e.getMessage());
            System.debug(DEBUG_PREFIX + e.getStackTraceString());

            response.valid = false;
            response.message = 'Invalid agreement.';
            return response;
        }

        if (agreement.Status__c == 'Signed') {
            response.valid = false;
            response.message = 'This agreement has already been signed.';
            return response;
        }

        if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
            response.valid = false;
            response.message = 'This signing link has expired.';
            return response;
        }

        response.valid = true;
        response.message = 'Success';
        response.agreementId = agreement.Id;
        response.agreementHtml = agreement.Agreement_HTML__c;
        response.clientEmail = agreement.Opportunity__r.Email__c;
        response.supervisorEmail = agreement.Opportunity__r.Supervisor_User_Email__c;
        response.status = agreement.Status__c;

        response.supportingFiles =
            ClientAgreementAttachmentService.getAgreementImageFilesExcludingAgreementAttachments(
                agreement.Opportunity__c,
                agreement.Id
            );

        System.debug(DEBUG_PREFIX + 'getAgreementById END - Success');
        return response;
    }

    @AuraEnabled
    public static void submitSignature(
        Id agreementId,
        String signatureBase64,
        String signedAgreementHtml,
        String signedPdfBase64
    ) {
        System.debug(DEBUG_PREFIX + 'submitSignature START');
        System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
        System.debug(DEBUG_PREFIX + 'Running User Name: ' + UserInfo.getName());
        System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());
        System.debug(DEBUG_PREFIX + 'Agreement Id received: ' + agreementId);
        System.debug(DEBUG_PREFIX + 'Signature Base64 length: ' + getStringLength(signatureBase64));
        System.debug(DEBUG_PREFIX + 'Signed Agreement HTML length: ' + getStringLength(signedAgreementHtml));
        System.debug(DEBUG_PREFIX + 'Signed PDF Base64 length: ' + getStringLength(signedPdfBase64));

        if (agreementId == null) {
            throw new AuraHandledException('Invalid agreement link.');
        }

        if (String.isBlank(signatureBase64)) {
            throw new AuraHandledException('Signature is required.');
        }

        if (String.isBlank(signedAgreementHtml)) {
            throw new AuraHandledException('Signed agreement HTML is required.');
        }

        if (String.isBlank(signedPdfBase64)) {
            throw new AuraHandledException('Signed PDF content is required.');
        }

        List<Client_Agreement__c> agreements = [
            SELECT Id,
                   Status__c,
                   Token_Expiry__c,
                   Opportunity__r.RecordTypeId
            FROM Client_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];

        if (agreements.isEmpty()) {
            throw new AuraHandledException('Invalid agreement link.');
        }

        Client_Agreement__c agreement = agreements[0];

        validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);

        if (agreement.Status__c == 'Signed') {
            throw new AuraHandledException('This agreement has already been signed.');
        }

        if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
            throw new AuraHandledException('This signing link has expired.');
        }

        Client_Agreement_Submission__c submission =
            new Client_Agreement_Submission__c();

        submission.Client_Agreement__c = agreementId;
        submission.Signature_Base64__c = signatureBase64;
        submission.Signed_Agreement_HTML__c = signedAgreementHtml;
        submission.Status__c = 'New';

        insert submission;

        insertPdfChunks(submission.Id, signedPdfBase64);

        Client_Agreement_Submission_Event__e eventRecord =
            new Client_Agreement_Submission_Event__e();

        eventRecord.Submission_Id__c = String.valueOf(submission.Id);

        Database.SaveResult publishResult = EventBus.publish(eventRecord);

        if (publishResult == null || !publishResult.isSuccess()) {
            String errorMessage = 'Failed to publish agreement submission event.';

            if (publishResult != null
                && publishResult.getErrors() != null
                && publishResult.getErrors().size() > 0) {
                errorMessage = publishResult.getErrors()[0].getMessage();
            }

            throw new AuraHandledException(errorMessage);
        }

        System.debug(DEBUG_PREFIX + 'Submission created and platform event published. Submission Id: ' + submission.Id);
        System.debug(DEBUG_PREFIX + 'submitSignature END - Success');
    }

    private static void insertPdfChunks(Id submissionId, String signedPdfBase64) {
        if (submissionId == null || String.isBlank(signedPdfBase64)) {
            return;
        }

        List<Client_Agreement_Submission_Chunk__c> chunks =
            new List<Client_Agreement_Submission_Chunk__c>();

        Integer sequence = 1;
        Integer startIndex = 0;
        Integer totalLength = signedPdfBase64.length();

        while (startIndex < totalLength) {
            Integer endIndex = Math.min(startIndex + PDF_CHUNK_SIZE, totalLength);

            Client_Agreement_Submission_Chunk__c chunkRecord =
                new Client_Agreement_Submission_Chunk__c();

            // Do not use lookup here for guest user.
            chunkRecord.Submission_Id__c = String.valueOf(submissionId);
            chunkRecord.Sequence__c = sequence;
            chunkRecord.Chunk_Data__c = signedPdfBase64.substring(startIndex, endIndex);

            chunks.add(chunkRecord);

            sequence++;
            startIndex = endIndex;
        }

        if (!chunks.isEmpty()) {
            insert chunks;
        }
    }

    private static void validateAreliaOpportunity(Id opportunityRecordTypeId) {
        if (opportunityRecordTypeId == null) {
            throw new AuraHandledException('Opportunity Record Type is missing.');
        }

        Map<Id, Schema.RecordTypeInfo> recordTypeMap =
            Schema.SObjectType.Opportunity.getRecordTypeInfosById();

        Schema.RecordTypeInfo rtInfo = recordTypeMap.get(opportunityRecordTypeId);

        if (rtInfo == null || rtInfo.getDeveloperName() != 'Arelia') {
            throw new AuraHandledException('Invalid agreement.');
        }
    }

    private static Integer getStringLength(String value) {
        return value == null ? 0 : value.length();
    }
}