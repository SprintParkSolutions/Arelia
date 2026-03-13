@IsTest
public class ProjectMilestoneControllerTest {

    @IsTest
    static void testGetMilestonesWithNullProjectId() {
        Test.startTest();
        ProjectMilestoneController.MilestoneResponse response =
            ProjectMilestoneController.getMilestones(null);
        Test.stopTest();

        System.assertNotEquals(null, response, 'Response should not be null');
        System.assertEquals(
            0,
            response.completionPercentage,
            'Completion percentage should be 0 for null project'
        );
        System.assertEquals(
            0,
            response.milestones.size(),
            'Milestones list should be empty for null project'
        );
    }

    @IsTest
    static void testGetMilestonesNoPaymentTerms() {
        Contact c = TestDataUtility.createContact(
            'Client',
            'client@test.com',
            'password123'
        );

        Project__c project = TestDataUtility.createProject(
            'Test Project',
            100000,
            c.Id
        );

        project.Project_Completion_Status__c = 30;
        update project;

        Test.startTest();
        ProjectMilestoneController.MilestoneResponse response =
            ProjectMilestoneController.getMilestones(project.Id);
        Test.stopTest();

        System.assertEquals(
            30,
            response.completionPercentage,
            'Completion percentage should match project value'
        );
        System.assertEquals(
            0,
            response.milestones.size(),
            'No milestones should exist when no payment terms are present'
        );
    }

    @IsTest
    static void testGetMilestonesWithPaymentTerms() {
        Contact c = TestDataUtility.createContact(
            'Client',
            'client2@test.com',
            'password123'
        );

        Project__c project = TestDataUtility.createProject(
            'Milestone Project',
            200000,
            c.Id
        );

        project.Project_Completion_Status__c = 60;
        update project;

        Payment_Term__c term1 =
            TestDataUtility.createPaymentTerm(project.Id, 'Advance', 40);
        term1.Payment_Received__c = true;
        update term1;

        Payment_Term__c term2 =
            TestDataUtility.createPaymentTerm(project.Id, 'Final', 30);
        term2.Payment_Received__c = false;
        update term2;

        Test.startTest();
        ProjectMilestoneController.MilestoneResponse response =
            ProjectMilestoneController.getMilestones(project.Id);
        Test.stopTest();

        System.assertEquals(
            60,
            response.completionPercentage,
            'Completion percentage should be 60'
        );
        System.assertEquals(
            2,
            response.milestones.size(),
            'Exactly two milestones should be returned'
        );

        ProjectMilestoneController.MilestoneDTO m1 = response.milestones[0];
        System.assertEquals(
            40,
            m1.cumulativePercentage,
            'First milestone cumulative percentage should be 40'
        );
        System.assertEquals(
            true,
            m1.completed,
            'First milestone should be marked completed'
        );
        System.assertEquals(
            true,
            m1.paymentReceived,
            'First milestone payment should be received'
        );

        ProjectMilestoneController.MilestoneDTO m2 = response.milestones[1];
        System.assertEquals(
            70,
            m2.cumulativePercentage,
            'Second milestone cumulative percentage should be 70'
        );
        System.assertEquals(
            false,
            m2.completed,
            'Second milestone should not be completed'
        );
        System.assertEquals(
            false,
            m2.paymentReceived,
            'Second milestone payment should not be received'
        );
    }

    @IsTest
    static void testExactCompletionMatch() {
        Contact c = TestDataUtility.createContact(
            'Exact Client',
            'exact@test.com',
            'password123'
        );

        Project__c project = TestDataUtility.createProject(
            'Exact Match Project',
            150000,
            c.Id
        );

        project.Project_Completion_Status__c = 50;
        update project;

        TestDataUtility.createPaymentTerm(project.Id, 'Milestone 1', 50);

        Test.startTest();
        ProjectMilestoneController.MilestoneResponse response =
            ProjectMilestoneController.getMilestones(project.Id);
        Test.stopTest();

        System.assertEquals(
            1,
            response.milestones.size(),
            'Exactly one milestone should be returned'
        );
        System.assertEquals(
            true,
            response.milestones[0].completed,
            'Milestone should be completed when completion equals cumulative percentage'
        );
    }
}