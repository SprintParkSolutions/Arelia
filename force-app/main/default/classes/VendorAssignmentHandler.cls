/**
 * @name        VendorAssignmentHandler
 * @description Handler class for VendorAssignmentTrigger.
 *              Calculates and updates Project__c.Project_Completion_Status__c
 *              based on related Vendor_Assignment__c records.
 * @author      YourName
 * @version     1.0
 */
public with sharing class VendorAssignmentHandler {
    private static final Decimal PENALTY_PER_DAY = 5; // percent points per delayed day

    /**
     * @name        updateProjectCompletion
     * @description Recalculates the average Completion__c of all Vendor_Assignment__c
     *              records related to each Project__c and updates
     *              Project_Completion_Status__c field on Project__c.
     * @param       projectIds - Set of Project__c record Ids to update.
     */
    public static void updateProjectCompletion(Set<Id> projectIds) {
        if (projectIds == null || projectIds.isEmpty()) {
            return;
        }

        // Map to store Vendor Assignments by Project Id
        Map<Id, List<Decimal>> projectCompletionMap = new Map<Id, List<Decimal>>();
        Map<Id, Decimal> vendorAmountMap = new Map<Id, Decimal>();

        for (AggregateResult ar : [
            SELECT Project__c, SUM(Vendor_Amount__c) totalAmount
            FROM Vendor_Assignment__c
            WHERE Project__c IN :projectIds
            GROUP BY Project__c
        ]) {
            vendorAmountMap.put((Id)ar.get('Project__c'), (Decimal)ar.get('totalAmount'));
        }

        // Fetch all Vendor Assignments for these projects
        List<Vendor_Assignment__c> assignments = [
            SELECT Project__c, Completion__c
            FROM Vendor_Assignment__c
            WHERE Project__c IN :projectIds
        ];

        // Group Completion values by Project
        for (Vendor_Assignment__c va : assignments) {
            if (!projectCompletionMap.containsKey(va.Project__c)) {
                projectCompletionMap.put(va.Project__c, new List<Decimal>());
            }

            if (va.Completion__c != null) {
                projectCompletionMap.get(va.Project__c).add(va.Completion__c);
            }
        }

        // Prepare list of projects to update
        List<Project__c> projectsToUpdate = new List<Project__c>();
         Map<Id, Project__c> projectMap = new Map<Id, Project__c>([
            SELECT Id, Remaining_Project_Budget__c
            FROM Project__c
            WHERE Id IN :projectIds
        ]);

        for (Id projectId : projectIds) {
             Project__c proj = projectMap.get(projectId);
            List<Decimal> completions = projectCompletionMap.get(projectId);
            Decimal avg = 0;

            if (completions != null && !completions.isEmpty()) {
                Decimal sum = 0;
                for (Decimal percent : completions) {
                    sum += percent;
                }
                avg = sum / completions.size();
            }

            Decimal vendorAssignedAmount = vendorAmountMap.containsKey(projectId) ? vendorAmountMap.get(projectId) : 0;
            // Decimal remainingBudget = proj.Remaining_Project_Budget__c != null ? proj.Remaining_Project_Budget__c : 0;
            // Decimal pendingAmount = remainingBudget - vendorAssignedAmount;
            // if (pendingAmount < 0) {pendingAmount = 0;}

            projectsToUpdate.add(new Project__c(
                Id = projectId,
                Project_Completion_Status__c = avg,
                Remaining_Budget_Pending__c = vendorAssignedAmount
            ));
        }

        // Perform update
        if (!projectsToUpdate.isEmpty()) {
            update projectsToUpdate;
        }
    }

    public static void calculateEfficiency(List<Vendor_Assignment__c> newAssignments) {

        for (Vendor_Assignment__c assignment : newAssignments) {
            
            // --- Condition Check ---
            // Only calculate if the necessary fields are populated and conditions are met
            if (
                assignment.Status__c == 'Completed' &&
                assignment.Completion__c == 100 &&
                assignment.Vendor_Work_Start_Date__c != null &&
                assignment.Vendor_Work_End_Date__c != null &&
                assignment.Vendor_Actual_Completion_Date__c != null
            ) {
                
                // --- On-Time or Early Completion ---
                if (assignment.Vendor_Actual_Completion_Date__c <= assignment.Vendor_Work_End_Date__c) {
                    assignment.Vendor_Efficiency__c = 100;
                } 
                // --- Delayed Completion ---
                else {
                    // Use Decimal for precision in calculations
                    Decimal plannedDuration = assignment.Vendor_Work_Start_Date__c.daysBetween(assignment.Vendor_Work_End_Date__c) + 1;
                    Decimal actualDuration = assignment.Vendor_Work_Start_Date__c.daysBetween(assignment.Vendor_Actual_Completion_Date__c) + 1;

                    // Avoid division by zero
                    if (actualDuration > 0) {
                        Decimal efficiency = (plannedDuration / actualDuration) * 100;
                        // Round to two decimal places for consistency
                        assignment.Vendor_Efficiency__c = efficiency.setScale(2); 
                    } else {
                        assignment.Vendor_Efficiency__c = 0;
                    }
                }
            }
            // Optional: If conditions are not met, you could clear the field
            else {
                assignment.Vendor_Efficiency__c = null;
            }
        }
    }
    public static void updateVendorAverageEfficiency(List<Vendor_Assignment__c> oldAssignments, List<Vendor_Assignment__c> newAssignments) {
        
        Set<Id> vendorIds = new Set<Id>();
        
        // Collect Vendor IDs from the records that were changed
        if (newAssignments != null) {
            for (Vendor_Assignment__c assignment : newAssignments) {
                if (assignment.Vendor__c != null) {
                    vendorIds.add(assignment.Vendor__c);
                }
            }
        }
        if (oldAssignments != null) {
            for (Vendor_Assignment__c assignment : oldAssignments) {
                if (assignment.Vendor__c != null) {
                    vendorIds.add(assignment.Vendor__c);
                }
            }
        }

        if (vendorIds.isEmpty()) {
            return; // No vendors to update
        }

        List<Vendor__c> vendorsToUpdate = new List<Vendor__c>();
        
        // Use an Aggregate Query to get the average efficiency for each affected Vendor
        // This is highly efficient and the main reason to use Apex here
        for (AggregateResult ar : [
            SELECT Vendor__c, AVG(Vendor_Efficiency__c) avgEff
            FROM Vendor_Assignment__c
            WHERE Vendor__c IN :vendorIds AND Status__c = 'Completed'
            GROUP BY Vendor__c
        ]) {
            Id vendorId = (Id) ar.get('Vendor__c');
            Decimal avg = (Decimal) ar.get('avgEff');

            Decimal safeAvg = (avg == null ? 0 : avg.setScale(2));

            vendorsToUpdate.add(new Vendor__c(
                Id = vendorId,
                Average_Efficiency__c = safeAvg
            ));
        }


        // Handle vendors who may now have zero completed assignments left
        Set<Id> vendorsWithAverages = (new Map<Id, SObject>(vendorsToUpdate)).keySet();
        for (Id vendorId : vendorIds) {
            if (!vendorsWithAverages.contains(vendorId)) {
                // If a vendor has no more completed assignments, set their average to 0
                vendorsToUpdate.add(new Vendor__c(Id = vendorId, Average_Efficiency__c = 0));
            }
        }

        if (!vendorsToUpdate.isEmpty()) {
            update vendorsToUpdate;
        }
    }
}