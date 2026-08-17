/**
 * @description Test class for VendorAgreementService.
 * Covers Vendor Agreement creation, save, send, signed restrictions,
 * vendor email validation, supervisor name population, and null input validation.
 */
@IsTest
@SuppressWarnings(
    'PMD.ExcessivePublicCount, PMD.ApexUnitTestClassShouldHaveAsserts, PMD.AvoidCatchingGenericException, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.ApexCRUDViolation, PMD.ApexDoc'
)
private class VendorAgreementServiceTest {
    private static final String VENDOR_EMAIL =
        'vendor.service.test@example.com';
    private static final String VENDOR_PHONE = '9876543210';
    private static final String VENDOR_ADDRESS =
        'Test Vendor Address, Hyderabad';
    private static final String AGREEMENT_HTML =
        '<p>Existing Agreement</p>';
    private static final String OPPORTUNITY_STAGE = 'Proposal';
    private static final String PROJECT_SCOPE = 'Dining Hall';
    private static final String CLIENT_AGREEMENT_OBJECT_API =
        'Client_Agreement__c';

    private class TestRecords {
        Id supervisorUserId;
        Id opportunityId;
        Id vendorId;
        Id vendorOpportunityId;
    }

    @IsTest
    private static void getAgreementShouldCreateDraftAgreement() {
        TestRecords records = createTestRecords();

        Test.startTest();

        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.getAgreement(
                records.vendorOpportunityId
            );

        Test.stopTest();

        Assert.isNotNull(
            response.agreementId,
            'Agreement Id should be returned.'
        );
        Assert.areEqual(
            VendorAgreementConstants.STATUS_DRAFT,
            response.agreementStatus,
            'Agreement should be created in Draft status.'
        );
        Assert.areEqual(
            VENDOR_EMAIL,
            response.vendorEmail,
            'Vendor email should be populated from Vendor.'
        );
        Assert.isTrue(
            response.agreementHtml.contains('Vendor Agreement')
                || response.agreementHtml.contains('VENDOR AGREEMENT'),
            'Agreement HTML should contain agreement content.'
        );

        Vendor_Agreement__c agreementRecord =
            getAgreementById(response.agreementId);

        Assert.areEqual(
            records.vendorOpportunityId,
            agreementRecord.Vendor_Opportunity__c,
            'Agreement should be linked to Vendor Opportunity.'
        );
        Assert.areEqual(
            records.opportunityId,
            agreementRecord.Opportunity__c,
            'Agreement should be linked to Opportunity.'
        );
        Assert.areEqual(
            records.vendorId,
            agreementRecord.Vendor__c,
            'Agreement should be linked to Vendor.'
        );
        Assert.isNotNull(
            agreementRecord.Supervisor_Name__c,
            'Supervisor name should be populated.'
        );
        Assert.isNotNull(
            agreementRecord.Supervisor_Email__c,
            'Supervisor email should be populated.'
        );
    }

    @IsTest
    private static void saveAgreementShouldUpdateSanitizedHtml() {
        TestRecords records = createTestRecords();

        VendorAgreementService.getAgreement(records.vendorOpportunityId);

        String updatedHtml =
            '<p>Updated Vendor Agreement</p><script>alert("xss")</script>';

        Test.startTest();

        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.saveAgreement(
                records.vendorOpportunityId,
                updatedHtml
            );

        Test.stopTest();

        Assert.isNotNull(
            response.agreementId,
            'Agreement Id should be returned after save.'
        );

        Vendor_Agreement__c agreementRecord =
            getAgreementById(response.agreementId);

        Assert.isTrue(
            agreementRecord.Agreement_HTML__c.contains(
                'Updated Vendor Agreement'
            ),
            'Updated agreement text should be saved.'
        );
        Assert.isFalse(
            agreementRecord.Agreement_HTML__c.contains('<script'),
            'Script tag should be sanitized.'
        );
    }

    @IsTest
    private static void saveAgreementShouldFailForSignedAgreement() {
        TestRecords records = createTestRecords();

        insertExistingAgreement(
            records,
            VendorAgreementConstants.STATUS_SIGNED,
            VENDOR_EMAIL,
            'Test Supervisor'
        );

        Test.startTest();

        try {
            VendorAgreementService.saveAgreement(
                records.vendorOpportunityId,
                '<p>Should not save</p>'
            );

            Assert.fail('Signed agreement should not be editable.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void sendAgreementShouldUpdateAgreementAndVendorOpportunity() {
        TestRecords records = createTestRecords();

        VendorAgreementService.getAgreement(records.vendorOpportunityId);

        Test.startTest();

        try {
            VendorAgreementService.sendAgreement(
                records.vendorOpportunityId
            );
        } catch (Exception exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'Email-related exception is acceptable in this service test.'
            );
        }

        Test.stopTest();

        Vendor_Agreement__c agreementRecord =
            getLatestAgreementByVendorOpportunity(
                records.vendorOpportunityId
            );

        Assert.areEqual(
            VendorAgreementConstants.STATUS_SENT,
            agreementRecord.Agreement_Status__c,
            'Agreement status should be Sent.'
        );
        Assert.isNotNull(
            agreementRecord.Unsigned_File_Id__c,
            'Unsigned file Id should be populated.'
        );
        Assert.isNotNull(
            agreementRecord.Signing_Link__c,
            'Signing link should be populated.'
        );
        Assert.areEqual(
            Date.today(),
            agreementRecord.Sent_Date__c,
            'Sent date should be today.'
        );

        Vendor_Opportunity__c vendorOpportunity = [
            SELECT Vendor_Agreement_Sent__c
            FROM Vendor_Opportunity__c
            WHERE Id = :records.vendorOpportunityId
            LIMIT 1
        ];

        Assert.areEqual(
            true,
            vendorOpportunity.Vendor_Agreement_Sent__c,
            'Vendor Agreement Sent checkbox should be checked.'
        );
    }

    @IsTest
    private static void sendAgreementShouldFailWhenAgreementAlreadySigned() {
        TestRecords records = createTestRecords();

        insertExistingAgreement(
            records,
            VendorAgreementConstants.STATUS_SIGNED,
            VENDOR_EMAIL,
            'Test Supervisor'
        );

        Test.startTest();

        try {
            VendorAgreementService.sendAgreement(
                records.vendorOpportunityId
            );

            Assert.fail('Signed agreement should not be sent again.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getAgreementShouldFailWhenVendorOpportunityIdIsNull() {
        Test.startTest();

        try {
            VendorAgreementService.getAgreement(null);

            Assert.fail('Null Vendor Opportunity Id should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getAgreementShouldFailWhenVendorEmailIsMissing() {
        TestRecords records = createTestRecords();

        update new Vendor__c(
            Id = records.vendorId,
            Email__c = null
        );

        Test.startTest();

        try {
            VendorAgreementService.getAgreement(
                records.vendorOpportunityId
            );

            Assert.fail('Missing vendor email should fail.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void getAgreementShouldPopulateMissingSupervisorName() {
        TestRecords records = createTestRecords();

        Vendor_Agreement__c agreementRecord =
            insertExistingAgreement(
                records,
                VendorAgreementConstants.STATUS_DRAFT,
                VENDOR_EMAIL,
                null
            );

        Test.startTest();

        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.getAgreement(
                records.vendorOpportunityId
            );

        Test.stopTest();

        Vendor_Agreement__c updatedAgreement =
            getAgreementById(agreementRecord.Id);

        Assert.areEqual(
            agreementRecord.Id,
            response.agreementId,
            'Existing agreement should be returned.'
        );
        Assert.isNotNull(
            updatedAgreement.Supervisor_Name__c,
            'Missing supervisor name should be populated.'
        );
    }

    @IsTest
    private static void sendAgreementShouldFailWhenExistingAgreementHasNoVendorEmail() {
        TestRecords records = createTestRecords();

        insertExistingAgreement(
            records,
            VendorAgreementConstants.STATUS_DRAFT,
            null,
            'Test Supervisor'
        );

        Test.startTest();

        try {
            VendorAgreementService.sendAgreement(
                records.vendorOpportunityId
            );

            Assert.fail('Agreement without vendor email should not be sent.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isNotNull(
                exceptionValue,
                'AuraHandledException should be thrown.'
            );
        }

        Test.stopTest();
    }

    @IsTest
    private static void saveAgreementShouldCreateAgreementWhenMissing() {
        TestRecords records = createTestRecords();

        Test.startTest();

        VendorAgreementService.AgreementResponse response =
            VendorAgreementService.saveAgreement(
                records.vendorOpportunityId,
                '<p>New agreement from save</p>'
            );

        Test.stopTest();

        Assert.isNotNull(
            response.agreementId,
            'Agreement should be created when save is called.'
        );
        Assert.areEqual(
            VendorAgreementConstants.STATUS_DRAFT,
            response.agreementStatus,
            'Agreement should remain Draft after save.'
        );

        Vendor_Agreement__c agreementRecord =
            getAgreementById(response.agreementId);

        Assert.isTrue(
            agreementRecord.Agreement_HTML__c.contains(
                'New agreement from save'
            ),
            'Saved HTML should be available on agreement.'
        );
    }

    private static TestRecords createTestRecords() {
        User supervisorUser =
            TestDataUtility.createSupervisorUser('vagsup');

        TestRecords records = new TestRecords();
        records.supervisorUserId = supervisorUser.Id;

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Opportunity opportunityRecord =
                createAreliaOpportunity(supervisorUser.Id);

            prepareClientAgreementForVendorOpportunity(
                opportunityRecord.Id
            );

            Vendor__c vendorRecord =
                createVendorRecord();

            Vendor_Opportunity__c vendorOpportunity =
                createVendorOpportunityRecord(
                    opportunityRecord.Id,
                    vendorRecord.Id
                );

            records.opportunityId = opportunityRecord.Id;
            records.vendorId = vendorRecord.Id;
            records.vendorOpportunityId = vendorOpportunity.Id;
        }

        return records;
    }

    private static Opportunity createAreliaOpportunity(Id supervisorUserId) {
        Account accountRecord = TestDataUtility.createAccount(
            'Vendor Agreement Test Account'
        );

        Opportunity opportunityRecord =
            TestDataUtility.createOpportunity(
                'Vendor Agreement Test Opportunity',
                supervisorUserId
            );

        opportunityRecord.AccountId = accountRecord.Id;
        opportunityRecord.StageName = OPPORTUNITY_STAGE;
        opportunityRecord.Project_Scope__c = PROJECT_SCOPE;

        update opportunityRecord;

        Assert.areEqual(
            AreliaUtility.getAreliaOpportunityRecordTypeId(),
            opportunityRecord.RecordTypeId,
            'Opportunity should keep Arelia Record Type from TestDataUtility.'
        );

        return opportunityRecord;
    }

    private static void prepareClientAgreementForVendorOpportunity(
        Id opportunityId
    ) {
        updateOpportunityAgreementFields(opportunityId);
        insertClientAgreementIfObjectExists(opportunityId);
    }

    private static void updateOpportunityAgreementFields(Id opportunityId) {
        Opportunity opportunityRecord =
            new Opportunity(Id = opportunityId);

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.Opportunity.fields.getMap();

        putBooleanIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Sent__c',
            true
        );
        putBooleanIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Signed__c',
            true
        );
        putBooleanIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Completed__c',
            true
        );
        putPicklistIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Status__c',
            'Signed'
        );
        putPicklistIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Agreement_Status__c',
            'Signed'
        );
        putDateIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Sent_Date__c',
            Date.today()
        );
        putDateIfUpdateable(
            opportunityRecord,
            fieldMap,
            'Client_Agreement_Signed_Date__c',
            Date.today()
        );

        Database.SaveResult updateResult =
            Database.update(opportunityRecord, false);

        Assert.isTrue(
            updateResult.isSuccess(),
            buildDatabaseErrorMessage(updateResult)
        );
    }

    private static void insertClientAgreementIfObjectExists(Id opportunityId) {
        Map<String, Schema.SObjectType> globalDescribe =
            Schema.getGlobalDescribe();

        if (!globalDescribe.containsKey(CLIENT_AGREEMENT_OBJECT_API)) {
            return;
        }

        Schema.SObjectType objectType =
            globalDescribe.get(CLIENT_AGREEMENT_OBJECT_API);

        SObject clientAgreement =
            objectType.newSObject();

        Map<String, Schema.SObjectField> fieldMap =
            objectType.getDescribe().fields.getMap();

        ContentVersion signedFile =
            TestDataUtility.createContentVersion(
                'Vendor Service Signed Client Agreement',
                'Signed client agreement file'
            );

        putReferenceIfCreateable(
            clientAgreement,
            fieldMap,
            'Opportunity__c',
            opportunityId
        );
        putPicklistIfCreateable(
            clientAgreement,
            fieldMap,
            'Status__c',
            'Signed'
        );
        putPicklistIfCreateable(
            clientAgreement,
            fieldMap,
            'Agreement_Status__c',
            'Signed'
        );
        putTextIfCreateable(
            clientAgreement,
            fieldMap,
            'Agreement_HTML__c',
            '<p>Signed Client Agreement</p>'
        );
        putTextIfCreateable(
            clientAgreement,
            fieldMap,
            'Signed_File_Id__c',
            String.valueOf(signedFile.Id)
        );
        putTextIfCreateable(
            clientAgreement,
            fieldMap,
            'Token__c',
            buildUniqueToken()
        );
        putDateTimeIfCreateable(
            clientAgreement,
            fieldMap,
            'Signed_Date__c',
            System.now()
        );
        putDateTimeIfCreateable(
            clientAgreement,
            fieldMap,
            'Sent_Date__c',
            System.now()
        );

        Database.SaveResult insertResult =
            Database.insert(clientAgreement, false);

        Assert.isTrue(
            insertResult.isSuccess(),
            buildDatabaseErrorMessage(insertResult)
        );
    }

    private static Vendor__c createVendorRecord() {
        Vendor__c vendorRecord =
            TestDataUtility.createVendor(
                'Vendor Agreement Test Vendor',
                getFirstActivePicklistValue(
                    Vendor__c.Vendor_Category__c
                ),
                VENDOR_EMAIL
            );

        vendorRecord.Phone__c = VENDOR_PHONE;
        vendorRecord.Address__c = VENDOR_ADDRESS;

        update vendorRecord;

        return vendorRecord;
    }

    private static Vendor_Opportunity__c createVendorOpportunityRecord(
        Id opportunityId,
        Id vendorId
    ) {
        Vendor_Opportunity__c vendorOpportunity =
            TestDataUtility.createVendorOpportunity(
                opportunityId,
                vendorId,
                getFirstActivePicklistValue(
                    Vendor_Opportunity__c.Vendor_Opportunity_Status__c
                )
            );

        Assert.isNotNull(
            vendorOpportunity.Id,
            'Vendor Opportunity should be created.'
        );

        return vendorOpportunity;
    }

    private static void putBooleanIfUpdateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        Boolean fieldValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isUpdateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.Boolean
        ) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static void putPicklistIfUpdateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        String preferredValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isUpdateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.Picklist
        ) {
            recordValue.put(
                fieldName,
                getPreferredPicklistValue(
                    fieldMap.get(fieldName),
                    preferredValue
                )
            );
        }
    }

    private static void putDateIfUpdateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        Date fieldValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isUpdateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.Date
        ) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static void putReferenceIfCreateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        Id fieldValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isCreateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.Reference
        ) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static void putPicklistIfCreateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        String preferredValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isCreateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.Picklist
        ) {
            recordValue.put(
                fieldName,
                getPreferredPicklistValue(
                    fieldMap.get(fieldName),
                    preferredValue
                )
            );
        }
    }

    private static void putTextIfCreateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        String fieldValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isCreateable()
            && isTextField(fieldMap.get(fieldName))
        ) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static void putDateTimeIfCreateable(
        SObject recordValue,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldName,
        Datetime fieldValue
    ) {
        if (
            fieldMap.containsKey(fieldName)
            && fieldMap.get(fieldName).getDescribe().isCreateable()
            && fieldMap.get(fieldName).getDescribe().getType()
                == Schema.DisplayType.DateTime
        ) {
            recordValue.put(fieldName, fieldValue);
        }
    }

    private static Boolean isTextField(Schema.SObjectField fieldToken) {
        Schema.DisplayType fieldType =
            fieldToken.getDescribe().getType();

        return fieldType == Schema.DisplayType.String
            || fieldType == Schema.DisplayType.TextArea;
    }

    private static String getPreferredPicklistValue(
        Schema.SObjectField fieldToken,
        String preferredValue
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (
                picklistValue.isActive()
                && picklistValue.getValue() == preferredValue
            ) {
                return picklistValue.getValue();
            }
        }

        return getFirstActivePicklistValue(fieldToken);
    }

    private static String getFirstActivePicklistValue(
        Schema.SObjectField fieldToken
    ) {
        List<Schema.PicklistEntry> picklistValues =
            fieldToken.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry picklistValue : picklistValues) {
            if (picklistValue.isActive()) {
                return picklistValue.getValue();
            }
        }

        Assert.fail(
            'No active picklist value found for '
                + fieldToken.getDescribe().getName()
        );

        return null;
    }

    private static String buildDatabaseErrorMessage(
        Database.SaveResult saveResult
    ) {
        if (
            saveResult == null
            || saveResult.isSuccess()
            || saveResult.getErrors().isEmpty()
        ) {
            return 'DML operation failed.';
        }

        return saveResult.getErrors()[0].getMessage();
    }

    private static Vendor_Agreement__c insertExistingAgreement(
        TestRecords records,
        String agreementStatus,
        String vendorEmail,
        String supervisorName
    ) {
        Vendor_Agreement__c agreementRecord =
            new Vendor_Agreement__c(
                Vendor_Opportunity__c = records.vendorOpportunityId,
                Opportunity__c = records.opportunityId,
                Vendor__c = records.vendorId,
                Agreement_HTML__c = AGREEMENT_HTML,
                Agreement_Status__c = agreementStatus,
                Vendor_Email__c = vendorEmail,
                Supervisor_Email__c = 'supervisor.test@example.com',
                Supervisor_Name__c = supervisorName
            );

        insert agreementRecord;

        return agreementRecord;
    }

    private static Vendor_Agreement__c getAgreementById(Id agreementId) {
        return [
            SELECT Id,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Vendor_Email__c,
                   Supervisor_Email__c,
                   Supervisor_Name__c,
                   Vendor_Opportunity__c,
                   Opportunity__c,
                   Vendor__c,
                   Unsigned_File_Id__c,
                   Signing_Link__c,
                   Sent_Date__c
            FROM Vendor_Agreement__c
            WHERE Id = :agreementId
            LIMIT 1
        ];
    }

    private static Vendor_Agreement__c getLatestAgreementByVendorOpportunity(
        Id vendorOpportunityId
    ) {
        return [
            SELECT Id,
                   Agreement_HTML__c,
                   Agreement_Status__c,
                   Vendor_Email__c,
                   Supervisor_Email__c,
                   Supervisor_Name__c,
                   Vendor_Opportunity__c,
                   Opportunity__c,
                   Vendor__c,
                   Unsigned_File_Id__c,
                   Signing_Link__c,
                   Sent_Date__c
            FROM Vendor_Agreement__c
            WHERE Vendor_Opportunity__c = :vendorOpportunityId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static String buildUniqueToken() {
        return 'token-' + String.valueOf(Crypto.getRandomInteger()).replace('-', '');
    }
}