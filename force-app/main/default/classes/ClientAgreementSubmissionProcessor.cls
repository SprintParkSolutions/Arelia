/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ClientAgreementSubmissionProcessor
 * Author          : <YourName>
 * Created Date    : Jun 23, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Jun 23, 2026
 * Description     : Processes Client Agreement guest submissions from platform event context.
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jun 23, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */


@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class ClientAgreementSubmissionProcessor {

    private static final String DEBUG_PREFIX = 'CLIENT_AGREEMENT_SUBMISSION_PROCESSOR_DEBUG: ';

    public static void processSubmissionIds(Set<Id> submissionIds) {
        if (submissionIds == null || submissionIds.isEmpty()) {
            return;
        }

        for (Id submissionId : submissionIds) {
            try {
                processSingleSubmission(submissionId);
            } catch (Exception e) {
                System.debug(DEBUG_PREFIX + 'Submission processing failed for Id: ' + submissionId);
                System.debug(DEBUG_PREFIX + e.getMessage());
                System.debug(DEBUG_PREFIX + e.getStackTraceString());

                markSubmissionFailed(submissionId, e.getMessage());
            }
        }
    }

    private static void processSingleSubmission(Id submissionId) {
        System.debug(DEBUG_PREFIX + 'START. Submission Id: ' + submissionId);
        System.debug(DEBUG_PREFIX + 'Running User Id: ' + UserInfo.getUserId());
        System.debug(DEBUG_PREFIX + 'Running User Type: ' + UserInfo.getUserType());

        List<Client_Agreement_Submission__c> submissions = [
            SELECT Id,
                   Client_Agreement__c,
                   Signature_Base64__c,
                   Signed_Agreement_HTML__c,
                   Status__c,
                   Error_Message__c,
                   Processed_Date__c
            FROM Client_Agreement_Submission__c
            WHERE Id = :submissionId
            LIMIT 1
        ];

        if (submissions.isEmpty()) {
            System.debug(DEBUG_PREFIX + 'No submission found.');
            return;
        }

        Client_Agreement_Submission__c submission = submissions[0];

        if (submission.Status__c == 'Processed') {
            System.debug(DEBUG_PREFIX + 'Submission already processed. Stopping.');
            return;
        }

        if (submission.Client_Agreement__c == null) {
            throw new AuraHandledException('Submission is missing Client Agreement reference.');
        }

        submission.Status__c = 'Processing';
        submission.Error_Message__c = null;
        update submission;

        String signedPdfBase64 = rebuildSignedPdfBase64(submission.Id);

        if (String.isBlank(signedPdfBase64)) {
            throw new AuraHandledException('Signed PDF content is missing from submission chunks.');
        }

        List<Client_Agreement__c> agreements = [
            SELECT Id,
                   Name,
                   Status__c,
                   Agreement_HTML__c,
                   Token__c,
                   Token_Expiry__c,
                   Signature_Base64__c,
                   Signed_Date__c,
                   Opportunity__c,
                   Opportunity__r.RecordTypeId
            FROM Client_Agreement__c
            WHERE Id = :submission.Client_Agreement__c
            LIMIT 1
        ];

        if (agreements.isEmpty()) {
            throw new AuraHandledException('Client Agreement record not found.');
        }

        Client_Agreement__c agreement = agreements[0];

        validateAreliaOpportunity(agreement.Opportunity__r.RecordTypeId);

        if (agreement.Status__c == 'Signed') {
            submission.Status__c = 'Processed';
            submission.Processed_Date__c = System.now();
            submission.Error_Message__c = 'Agreement was already signed.';
            update submission;
            return;
        }

        if (agreement.Token_Expiry__c != null && agreement.Token_Expiry__c < System.now()) {
            agreement.Status__c = 'Expired';
            update agreement;

            submission.Status__c = 'Failed';
            submission.Processed_Date__c = System.now();
            submission.Error_Message__c = 'Signing link expired.';
            update submission;
            return;
        }

        agreement.Signature_Base64__c = submission.Signature_Base64__c;
        agreement.Signed_Date__c = System.now();
        agreement.Agreement_HTML__c = submission.Signed_Agreement_HTML__c;
        agreement.Status__c = 'Signed';
        agreement.Token__c = null;

        System.debug(DEBUG_PREFIX + 'Attempting Client_Agreement__c update.');

        update agreement;

        System.debug(DEBUG_PREFIX + 'Client_Agreement__c update successful.');

        submission.Status__c = 'Processed';
        submission.Processed_Date__c = System.now();
        submission.Error_Message__c = null;
        update submission;

        System.debug(DEBUG_PREFIX + 'Enqueueing ClientAgreementSignedPdfJob.');

        System.enqueueJob(
            new ClientAgreementSignedPdfJob(
                agreement.Id,
                signedPdfBase64
            )
        );

        System.debug(DEBUG_PREFIX + 'END - Success.');
    }

    private static String rebuildSignedPdfBase64(Id submissionId) {
		if (submissionId == null) {
			return null;
		}

		List<Client_Agreement_Submission_Chunk__c> chunks = [
			SELECT Id,
				Sequence__c,
				Chunk_Data__c,
				Submission_Id__c
			FROM Client_Agreement_Submission_Chunk__c
			WHERE Submission_Id__c = :String.valueOf(submissionId)
			ORDER BY Sequence__c ASC
		];

		String combined = '';

		for (Client_Agreement_Submission_Chunk__c chunkRecord : chunks) {
			if (String.isBlank(chunkRecord.Chunk_Data__c)) {
				continue;
			}

			combined += chunkRecord.Chunk_Data__c;
		}

		return combined;
	}

    private static void markSubmissionFailed(Id submissionId, String errorMessage) {
        if (submissionId == null) {
            return;
        }

        try {
            Client_Agreement_Submission__c failedSubmission =
                new Client_Agreement_Submission__c();

            failedSubmission.Id = submissionId;
            failedSubmission.Status__c = 'Failed';
            failedSubmission.Processed_Date__c = System.now();
            failedSubmission.Error_Message__c = leftSafe(errorMessage, 100000);

            update failedSubmission;
        } catch (Exception e) {
            System.debug(DEBUG_PREFIX + 'Could not mark submission failed: ' + e.getMessage());
            System.debug(DEBUG_PREFIX + e.getStackTraceString());
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

    private static String leftSafe(String value, Integer maxLength) {
        if (String.isBlank(value)) {
            return null;
        }

        if (maxLength == null || maxLength <= 0) {
            return value;
        }

        return value.length() > maxLength ? value.left(maxLength) : value;
    }
}