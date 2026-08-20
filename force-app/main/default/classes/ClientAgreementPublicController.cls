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