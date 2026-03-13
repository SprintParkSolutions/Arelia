global class TaskAlertScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        Database.executeBatch(new TaskAlertBatch(), 200);
    }
}