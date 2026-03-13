@RestResource(urlMapping='/mobileVendorTasksV2')
global without sharing class MobileVendorTasksServiceV2 {

    // ===================== TASK DTO =====================
    global class TaskDTO {
        public String  taskName;
        public Date    dueDate;
        public Date    startDate;                 // ✅ NEW
        public Date    completedDate;             // ✅ NEW
        public String  status;
        public Decimal assignedPercentage;
    }

    // ===================== SUMMARY DTO =====================
    global class SummaryDTO {
        public Integer totalTasks;
        public Integer completedTasks;
        public Integer incompleteTasks;
    }

    // ===================== RESPONSE DTO =====================
    global class ResponseDTO {
        public Boolean success;
        public String  message;
        public List<TaskDTO> tasks;
        public SummaryDTO summary;
    }

    // ===================== API =====================
    @HttpPost
    global static ResponseDTO getVendorTasks() {

        ResponseDTO resp = new ResponseDTO();
        resp.success = false;
        resp.tasks   = new List<TaskDTO>();
        resp.summary = new SummaryDTO();

        try {
            String rawBody = RestContext.request.requestBody == null
                ? null
                : RestContext.request.requestBody.toString();

            Map<String, Object> input =
                (rawBody == null || rawBody.trim() == '')
                ? new Map<String, Object>()
                : (Map<String, Object>) JSON.deserializeUntyped(rawBody);

            String projectId   = (String) input.get('projectId');
            String vendorName  = (String) input.get('vendorName');
            Boolean summaryOnly = (Boolean) input.get('summaryOnly');

            if (String.isBlank(projectId) || String.isBlank(vendorName)) {
                resp.message = 'Missing projectId or vendorName';
                return resp;
            }

            Vendor_Assignment__c va = [
                SELECT Id
                FROM Vendor_Assignment__c
                WHERE Project__c = :projectId
                AND Vendor__r.Name = :vendorName
                LIMIT 1
            ];

            // 🔹 ONLY ADDING FIELDS – NO LOGIC CHANGE
            List<Task> tasks = [
                SELECT
                    Subject,
                    Status,
                    ActivityDate,
                    Start_Date__c,
                    Final_Task_Completed_Date__c,
                    Assigned_Percentage__c
                FROM Task
                WHERE WhatId = :va.Id
            ];

            Integer total = tasks.size();
            Integer completed = 0;

            for (Task t : tasks) {

                if (t.Status == 'Completed') {
                    completed++;
                }

                // 🔹 Existing behavior preserved
                if (summaryOnly != true) {
                    TaskDTO dto = new TaskDTO();
                    dto.taskName = t.Subject;
                    dto.status   = t.Status;
                    dto.dueDate  = t.ActivityDate;

                    // ✅ NEW MAPPINGS (SAFE)
                    dto.startDate     = t.Start_Date__c;
                    dto.completedDate = t.Final_Task_Completed_Date__c;

                    dto.assignedPercentage = t.Assigned_Percentage__c;
                    resp.tasks.add(dto);
                }
            }

            resp.summary.totalTasks      = total;
            resp.summary.completedTasks  = completed;
            resp.summary.incompleteTasks = total - completed;

            resp.success = true;
            resp.message = 'Success';
            return resp;

        } catch (Exception e) {
            resp.success = false;
            resp.message = e.getMessage();
            return resp;
        }
    }
}