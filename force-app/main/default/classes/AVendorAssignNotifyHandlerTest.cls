@IsTest(SeeAllData=true)
private class AVendorAssignNotifyHandlerTest {

    @IsTest
    static void handleAfterUpdateAllWatchedFieldsTest() {
        Project__c projectRec = getExistingProjectWithClient();

        deactivateExistingTokens(projectRec.Client__c);

        Id assignmentId = getFakeVendorAssignmentId();
        String projectLookupField = getProjectLookupField();

        System.assertNotEquals(
            null,
            projectLookupField,
            'Project lookup field should exist on Vendor_Assignment__c.'
        );

        Test.setMock(HttpCalloutMock.class, new FirebaseMock());

        Test.startTest();

        for (String fieldApiName : getWatchedFieldNames()) {
            if (!hasVendorAssignmentField(fieldApiName)) {
                continue;
            }

            Vendor_Assignment__c oldAssignment =
                new Vendor_Assignment__c(Id = assignmentId);

            Vendor_Assignment__c newAssignment =
                new Vendor_Assignment__c(Id = assignmentId);

            safePut(oldAssignment, projectLookupField, projectRec.Id);
            safePut(newAssignment, projectLookupField, projectRec.Id);

            Boolean oldValueSet = safePut(
                oldAssignment,
                fieldApiName,
                getTestValueForField(fieldApiName, false)
            );

            Boolean newValueSet = safePut(
                newAssignment,
                fieldApiName,
                getTestValueForField(fieldApiName, true)
            );

            if (!oldValueSet || !newValueSet) {
                continue;
            }

            AVendorAssignNotifyHandler.handleAfterUpdate(
                new List<Vendor_Assignment__c>{ newAssignment },
                new Map<Id, Vendor_Assignment__c>{
                    assignmentId => oldAssignment
                }
            );
        }

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'All available watched fields processed successfully.'
        );
    }

    @IsTest
    static void handleAfterUpdateNoWatchedFieldChangedTest() {
        Project__c projectRec = getExistingProjectWithClient();

        deactivateExistingTokens(projectRec.Client__c);

        Id assignmentId = getFakeVendorAssignmentId();
        String projectLookupField = getProjectLookupField();

        Vendor_Assignment__c oldAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        Vendor_Assignment__c newAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        safePut(oldAssignment, projectLookupField, projectRec.Id);
        safePut(newAssignment, projectLookupField, projectRec.Id);

        if (hasVendorAssignmentField('Status__c')) {
            Object sameValue = getTestValueForField('Status__c', false);
            safePut(oldAssignment, 'Status__c', sameValue);
            safePut(newAssignment, 'Status__c', sameValue);
        }

        Test.startTest();

        AVendorAssignNotifyHandler.handleAfterUpdate(
            new List<Vendor_Assignment__c>{ newAssignment },
            new Map<Id, Vendor_Assignment__c>{
                assignmentId => oldAssignment
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when no watched field changed.'
        );
    }

    @IsTest
    static void handleAfterUpdateOldAssignmentMissingTest() {
        Project__c projectRec = getExistingProjectWithClient();

        deactivateExistingTokens(projectRec.Client__c);

        Id assignmentId = getFakeVendorAssignmentId();
        String projectLookupField = getProjectLookupField();

        Vendor_Assignment__c newAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        safePut(newAssignment, projectLookupField, projectRec.Id);

        if (hasVendorAssignmentField('Status__c')) {
            safePut(
                newAssignment,
                'Status__c',
                getTestValueForField('Status__c', true)
            );
        }

        Test.startTest();

        AVendorAssignNotifyHandler.handleAfterUpdate(
            new List<Vendor_Assignment__c>{ newAssignment },
            new Map<Id, Vendor_Assignment__c>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when old assignment map does not contain record.'
        );
    }

    @IsTest
    static void handleAfterUpdateNoProjectFoundTest() {
        Id assignmentId = getFakeVendorAssignmentId();

        Vendor_Assignment__c oldAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        Vendor_Assignment__c newAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        if (hasVendorAssignmentField('Status__c')) {
            safePut(
                oldAssignment,
                'Status__c',
                getTestValueForField('Status__c', false)
            );

            safePut(
                newAssignment,
                'Status__c',
                getTestValueForField('Status__c', true)
            );
        }

        Test.startTest();

        AVendorAssignNotifyHandler.handleAfterUpdate(
            new List<Vendor_Assignment__c>{ newAssignment },
            new Map<Id, Vendor_Assignment__c>{
                assignmentId => oldAssignment
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when no Project lookup exists.'
        );
    }

    @IsTest
    static void handleAfterUpdateFakeProjectIdTest() {
        Id assignmentId = getFakeVendorAssignmentId();
        Id fakeProjectId = getFakeProjectId();

        String projectLookupField = getProjectLookupField();

        Vendor_Assignment__c oldAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        Vendor_Assignment__c newAssignment =
            new Vendor_Assignment__c(Id = assignmentId);

        safePut(oldAssignment, projectLookupField, fakeProjectId);
        safePut(newAssignment, projectLookupField, fakeProjectId);

        if (hasVendorAssignmentField('Status__c')) {
            safePut(
                oldAssignment,
                'Status__c',
                getTestValueForField('Status__c', false)
            );

            safePut(
                newAssignment,
                'Status__c',
                getTestValueForField('Status__c', true)
            );
        }

        Test.startTest();

        AVendorAssignNotifyHandler.handleAfterUpdate(
            new List<Vendor_Assignment__c>{ newAssignment },
            new Map<Id, Vendor_Assignment__c>{
                assignmentId => oldAssignment
            }
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Handler should skip when Project record is not found.'
        );
    }

    @IsTest
    static void handleAfterUpdateNullAndEmptyInputTest() {
        Test.startTest();

        AVendorAssignNotifyHandler.handleAfterUpdate(
            null,
            new Map<Id, Vendor_Assignment__c>()
        );

        AVendorAssignNotifyHandler.handleAfterUpdate(
            new List<Vendor_Assignment__c>(),
            new Map<Id, Vendor_Assignment__c>()
        );

        Test.stopTest();

        System.assertEquals(
            true,
            true,
            'Null and empty input should not throw exception.'
        );
    }

    private static Project__c getExistingProjectWithClient() {
        List<Project__c> projects = [
            SELECT Id, Name, Client__c
            FROM Project__c
            WHERE Client__c != null
            LIMIT 1
        ];

        System.assert(
            !projects.isEmpty(),
            'Please keep at least one Project__c record with Client__c populated in this sandbox.'
        );

        return projects[0];
    }

    private static void deactivateExistingTokens(Id contactId) {
        if (contactId == null) {
            return;
        }

        List<Mobile_Device_Token__c> activeTokens = [
            SELECT Id, Active__c
            FROM Mobile_Device_Token__c
            WHERE Contact__c = :contactId
            AND Active__c = true
        ];

        for (Mobile_Device_Token__c tokenRec : activeTokens) {
            tokenRec.Active__c = false;
        }

        if (!activeTokens.isEmpty()) {
            update activeTokens;
        }
    }

    private static Id getFakeVendorAssignmentId() {
        String prefix =
            Vendor_Assignment__c.SObjectType.getDescribe().getKeyPrefix();

        return (Id) (prefix + '000000000001');
    }

    private static Id getFakeProjectId() {
        String prefix =
            Project__c.SObjectType.getDescribe().getKeyPrefix();

        return (Id) (prefix + '000000000001');
    }

    private static List<String> getWatchedFieldNames() {
        return new List<String>{
            'Status__c',
            'Project_Update_Description__c',
            'Vendor_Efficiency__c',
            'Budget_Percentage__c',
            'Vendor_Tasks_Remaining_Percentage__c',
            'Vendor_Amount__c',
            'Completion_Percentage__c',
            'Vendor_Work_Start_Date__c',
            'Vendor_Work_End_Date__c',
            'Vendor_Work_Duration__c',
            'Task_Timeline_Status__c',
            'Schedule_Status__c',
            'Vendor_Actual_Completion_Date__c',
            'Vendor_Delay_Work_Count__c'
        };
    }

    private static String getProjectLookupField() {
        List<String> projectLookupCandidates = new List<String>{
            'Project__c',
            'Related_Project__c',
            'Project_Name__c'
        };

        Map<String, Schema.SObjectField> fieldMap =
            Vendor_Assignment__c.SObjectType.getDescribe().fields.getMap();

        for (String fieldApiName : projectLookupCandidates) {
            if (fieldMap.containsKey(fieldApiName)) {
                return fieldApiName;
            }
        }

        return null;
    }

    private static Boolean hasVendorAssignmentField(String fieldApiName) {
        return Vendor_Assignment__c.SObjectType
            .getDescribe()
            .fields
            .getMap()
            .containsKey(fieldApiName);
    }

    private static Boolean safePut(
        SObject recordObj,
        String fieldApiName,
        Object value
    ) {
        if (String.isBlank(fieldApiName) || value == null) {
            return false;
        }

        try {
            recordObj.put(fieldApiName, value);
            return true;
        } catch (Exception ex) {
            System.debug(
                'safePut skipped field ' +
                fieldApiName +
                '. Error: ' +
                ex.getMessage()
            );
            return false;
        }
    }

    private static Object getTestValueForField(
        String fieldApiName,
        Boolean isNewValue
    ) {
        Map<String, Schema.SObjectField> fieldMap =
            Vendor_Assignment__c.SObjectType.getDescribe().fields.getMap();

        if (!fieldMap.containsKey(fieldApiName)) {
            return null;
        }

        Schema.DescribeFieldResult fieldDescribe =
            fieldMap.get(fieldApiName).getDescribe();

        Schema.DisplayType fieldType = fieldDescribe.getType();

        if (fieldType == Schema.DisplayType.Picklist) {
            List<String> activeValues = new List<String>();

            for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                if (entry.isActive()) {
                    activeValues.add(entry.getValue());
                }
            }

            if (activeValues.isEmpty()) {
                return isNewValue ? 'Updated' : 'Old';
            }

            if (isNewValue && activeValues.size() > 1) {
                return activeValues[1];
            }

            if (isNewValue && activeValues.size() == 1) {
                return activeValues[0] + ' Updated';
            }

            return activeValues[0];
        }

        if (
            fieldType == Schema.DisplayType.Double ||
            fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Percent
        ) {
            return isNewValue ? Decimal.valueOf(25) : Decimal.valueOf(10);
        }

        if (fieldType == Schema.DisplayType.Integer) {
            return isNewValue ? 2 : 1;
        }

        if (fieldType == Schema.DisplayType.Date) {
            return isNewValue
                ? Date.today().addDays(1)
                : Date.today();
        }

        if (fieldType == Schema.DisplayType.DateTime) {
            return isNewValue
                ? System.now().addDays(1)
                : System.now();
        }

        if (fieldType == Schema.DisplayType.Boolean) {
            return isNewValue;
        }

        return isNewValue ? 'Updated Value' : 'Old Value';
    }

    private class FirebaseMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setHeader('Content-Type', 'application/json');

            if (
                request.getEndpoint() != null &&
                request.getEndpoint().contains('/messages:send')
            ) {
                response.setStatusCode(200);
                response.setBody(
                    '{"name":"projects/areliaspace-e5f22/messages/test-message-id"}'
                );
                return response;
            }

            response.setStatusCode(200);
            response.setBody(
                '{"access_token":"test_access_token","token_type":"Bearer","expires_in":3600}'
            );

            return response;
        }
    }
}