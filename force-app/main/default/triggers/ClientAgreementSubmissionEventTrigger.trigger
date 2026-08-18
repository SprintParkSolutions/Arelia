trigger ClientAgreementSubmissionEventTrigger on Client_Agreement_Submission_Event__e (after insert) {
    Set<Id> submissionIds = new Set<Id>();

    for (Client_Agreement_Submission_Event__e eventRecord : Trigger.New) {
        if (String.isBlank(eventRecord.Submission_Id__c)) {
            continue;
        }

        try {
            submissionIds.add((Id) eventRecord.Submission_Id__c);
        } catch (Exception e) {
            System.debug('Invalid Submission_Id__c on platform event: ' + eventRecord.Submission_Id__c);
        }
    }

    if (!submissionIds.isEmpty()) {
        ClientAgreementSubmissionProcessor.processSubmissionIds(submissionIds);
    }
}