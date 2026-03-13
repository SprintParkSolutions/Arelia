/**
 * @File Name         : ProjectStatusControllerTest.cls
 * @Description       : Unit tests for ProjectStatusController.loginAndFetch.
 * @Author            :
 * @Last Modified By  :
 * @Last Modified On  :
 * @Modification Log  :
 * =============================================================================
 * Ver   | Date       | Author   | Modification
 * =============================================================================
 * 1.0   |            |          | Initial Version
 * =============================================================================
 *
 * PMD Notes:
 * - Uses @TestSetup for common data creation (performance best practice).
 * - Each test method includes System.assert* calls
 *   (ApexUnitTestClassShouldHaveAsserts compliant).
 * - Test data is created via TestDataUtility helpers to avoid duplication.
 */
@IsTest
private class ProjectStatusControllerTest {

    // Reuse the same login values in tests
    private static final String LOGIN_EMAIL    = 'test@example.com';
    private static final String LOGIN_PASSWORD = 'Secret123';

    /* =========================================================
       TEST DATA SETUP
    ========================================================== */
    @TestSetup
    static void setupData() {
        // 1) Contact used for successful login
        //    (Assumes your TestDataUtility has a 3-arg createContact overload)
        Contact contactDetails = TestDataUtility.createContact('Project User', LOGIN_EMAIL, LOGIN_PASSWORD);

        // 2) Project__c details (using your utility)
        //    (Assumes your utility method signature: createProject(String, Decimal/Number))
        Project__c projectDetails = TestDataUtility.createProject('Project Name', 50000, contactDetails.Id);

        // 3) Vendor_Assignment__c details (using your utility)
        //    (Assumes your method signature: createVendorAssignment(Id, Decimal/Number))
        Vendor_Assignment__c vaDetails = TestDataUtility.createVendorAssignment(projectDetails.Id, 40);

        // 4) Task details (for the vendor table)
        //    (Assumes your method signature: createTask(String status, Id vaId, Decimal/Number))
        Task taskDetails = TestDataUtility.createTask('In Progress', vaDetails.Id, 20);
    }

    /* =========================================================
       TESTS
    ========================================================== */

    @IsTest
    static void testLoginSuccessWithProjects() {
        // act
        Test.startTest();
        ProjectStatusController.AuthResponseDTO res =
            ProjectStatusController.loginAndFetch(LOGIN_EMAIL, LOGIN_PASSWORD);
        Test.stopTest();

        // assert – basic response
        System.assertNotEquals(null, res, 'Response should not be null.');
        System.assertEquals(true, res.success, 'Success flag should be true.');
        System.assertEquals('Success', res.message, 'Message should be "Success".');
        System.assertEquals(1, res.projects.size(), 'Should return exactly one project.');

        // assert – project mapping
        ProjectStatusController.ProjectDTO projDto = res.projects[0];
        System.assertEquals('Project Name', projDto.name, 'Project name mismatch.');
        System.assertNotEquals(
            null,
            projDto.vendorAssignments,
            'Vendor assignments list should not be null.'
        );
        System.assertEquals(
            1,
            projDto.vendorAssignments.size(),
            'Project should have one vendor assignment.'
        );

        // assert – vendor mapping
        ProjectStatusController.VendorAssignmentDTO vaDto =
            projDto.vendorAssignments[0];

        System.assertNotEquals(
            null,
            vaDto.tasks,
            'Vendor tasks list should not be null.'
        );
        System.assert(
            !vaDto.tasks.isEmpty(),
            'Vendor assignment should have at least one task.'
        );

        // Light sanity checks on one task
        ProjectStatusController.TaskDTO tDto = vaDto.tasks[0];
        System.assertNotEquals(null, tDto.subject, 'Task subject should be populated.');
        System.assertNotEquals(null, tDto.status,  'Task status should be populated.');
    }

    @IsTest
    static void testLoginInvalidCredentials() {
        // act
        Test.startTest();
        ProjectStatusController.AuthResponseDTO res =
            ProjectStatusController.loginAndFetch('wrong@example.com', 'BadPassword');
        Test.stopTest();

        // assert
        System.assertNotEquals(null, res, 'Response should not be null.');
        System.assertEquals(false, res.success, 'Success flag should be false.');
        System.assertEquals(
            'Invalid email or password.',
            res.message,
            'Error message should indicate invalid credentials.'
        );
        System.assertEquals(
            0,
            res.projects.size(),
            'No projects should be returned for invalid credentials.'
        );
    }

    @IsTest
    static void testLoginNoProjects() {
        // arrange – contact with valid credentials but **no projects**
        TestDataUtility.createContact('NoProj User', 'noproject@example.com', LOGIN_PASSWORD);

        // act
        Test.startTest();
        ProjectStatusController.AuthResponseDTO res =
            ProjectStatusController.loginAndFetch('noproject@example.com', LOGIN_PASSWORD);
        Test.stopTest();

        // assert
        System.assertNotEquals(null, res, 'Response should not be null.');
        System.assertEquals(
            true,
            res.success,
            'Call should succeed even when no projects are found.'
        );
        System.assertEquals(
            'No projects found for this contact.',
            res.message,
            'Message should indicate no projects found.'
        );
        System.assertEquals(
            0,
            res.projects.size(),
            'Projects list should be empty for this contact.'
        );
    }
}