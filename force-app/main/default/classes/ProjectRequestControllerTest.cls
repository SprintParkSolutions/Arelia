/**
 * @FileName    : ProjectRequestControllerTest.cls
 * @Description : Test class for ProjectRequestController to ensure PMD compliance and high code coverage.
 */
@IsTest
private class ProjectRequestControllerTest {

    @TestSetup
    static void setupTestData() {
        // Utilizing the provided TestDataUtility to create a context user
        TestDataUtility.createSupervisorUser('prjReq');
    }

    @IsTest
    static void testGetProjectQuotationTypeValues() {
        // Retrieve the test user created in the @TestSetup method
        User contextUser = [SELECT Id FROM User WHERE Alias = 'prjReq' LIMIT 1];

        System.runAs(contextUser) {
            Test.startTest();
            // Call the target method
            List<ProjectRequestController.PicklistOptionDTO> options = ProjectRequestController.getProjectQuotationTypeValues();
            Test.stopTest();

            // 1. Assert that the returned list is never null
            System.assertNotEquals(null, options, 'The options list should not be null.');

            // 2. Dynamically calculate expected active picklist values to avoid hardcoding
            Integer expectedActiveValuesCount = 0;
            Schema.DescribeFieldResult fieldResult = Lead.Project_Request_Quotation_Type__c.getDescribe();
            for (Schema.PicklistEntry pe : fieldResult.getPicklistValues()) {
                if (pe.isActive()) {
                    expectedActiveValuesCount++;
                }
            }

            // 3. Verify the size of the returned list matches the active picklist values in the org
            System.assertEquals(
                expectedActiveValuesCount, 
                options.size(), 
                'The number of returned DTOs must match the exact count of active picklist values on the field.'
            );

            // 4. Validate the DTO properties if the list is populated
            if (!options.isEmpty()) {
                System.assertNotEquals(null, options[0].label, 'The picklist label should be populated.');
                System.assertNotEquals(null, options[0].value, 'The picklist value should be populated.');
            }
        }
    }
}