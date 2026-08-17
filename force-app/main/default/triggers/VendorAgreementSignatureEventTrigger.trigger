trigger VendorAgreementSignatureEventTrigger on Vendor_Agreement_Signature_Event__e(after insert) {
	Set<Id> signatureRequestIds = new Set<Id>();

    for (
        Vendor_Agreement_Signature_Event__e eventRecord
        : Trigger.new
    ) {
        if (
            String.isBlank(
                eventRecord.Signature_Request_Id__c
            )
        ) {
            continue;
        }

        try {
            signatureRequestIds.add(
                (Id) eventRecord.Signature_Request_Id__c
            );
        } catch (Exception exceptionValue) {
            System.debug(
                'Invalid Vendor Agreement Signature Request Id: '
                + eventRecord.Signature_Request_Id__c
            );
        }
    }

    if (!signatureRequestIds.isEmpty()) {
        VendorAgreementSignProcessor.processSignatureRequestIds(signatureRequestIds);
    }
}