/**
 * @description  Scheduler class to run the ProjectReminderBatch every schedule execution.
 *               Uses global because Schedulable classes must be global when invoked externally.
 * @author       
 * @createdDate  
 *
 * PMD Notes:
 *  - Suppressing AvoidGlobalModifier because Schedulable classes REQUIRE global scope.
 *  - Suppressing ApexSharingViolations because scheduler does not access data directly.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier, PMD.ApexSharingViolations')
global without sharing class ProjectReminderBatchScheduler implements Schedulable {

    /**
     * @description Executes the ProjectReminderBatch with batch size 200.
     *              Database.executeBatch is safe here; the batch class handles CRUD/FLS.
     */
    global void execute(SchedulableContext sc) {            
        Database.executeBatch(new ProjectReminderBatch(), 200);
    }
}