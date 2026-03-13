@IsTest
private class TaskAlertSchedulerTest {

    @IsTest
    static void testSchedulerExecution() {
        // Define a Cron Expression (e.g., Run at midnight every day)
        String cronExp = '0 0 0 * * ?';
        
        Test.startTest();
        // Schedule the job
        String jobId = System.schedule(
            'Test Task Alert Scheduler', 
            cronExp, 
            new TaskAlertScheduler()
        );
        Test.stopTest(); // Forces the Schedulable execute() method to run, which queues the TaskAlertBatch

        // Verify that the job was scheduled successfully
        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime 
            FROM CronTrigger 
            WHERE Id = :jobId
        ];
        
        Assert.areEqual(cronExp, ct.CronExpression, 'The cron expression should match the one provided.');
        Assert.isNotNull(ct.NextFireTime, 'The job should have a next fire time scheduled.');
        
        // Note: The actual processing logic of the batch should be tested in a separate 'TaskAlertBatchTest' class.
        // This test confirms the Scheduler successfully instantiates and fires the Batch without errors.
    }
}