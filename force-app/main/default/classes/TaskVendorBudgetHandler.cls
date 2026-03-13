// File: TaskVendorBudgetHandler.cls
// Enforces that the sum of Task.Assigned_Percentage__c for all Tasks whose
// WhatId = a Vendor_Assignment__c never exceeds Vendor_Assignment__c.Budget_Percentage__c.
// Also maintains Vendor_Assignment__c.Vendor_Tasks_Remaining_Percentage__c.
public without sharing class TaskVendorBudgetHandler {


    // =========================
    // 1) VALIDATION (BEFORE DML)
    // =========================
    public static void validatePercentTotals(List<Task> newList, Map<Id, Task> oldMap) {
        if (newList == null || newList.isEmpty()) return;

        String vaPrefix = vaKeyPrefix();

        // collect Vendor_Assignment__c ids referenced by new/old WhatId
        Set<Id> vaIds = new Set<Id>();
        Set<Id> contextTaskIds = new Set<Id>();
        for (Task t : newList) {
            if (t.Id != null) contextTaskIds.add(t.Id);
            if (isVA(t.WhatId, vaPrefix)) vaIds.add(t.WhatId);
        }
        if (oldMap != null) {
            for (Task o : oldMap.values()) {
                if (isVA(o.WhatId, vaPrefix)) vaIds.add(o.WhatId);
            }
        }
        if (vaIds.isEmpty()) return;

        // existing totals in DB (exclude the rows currently in the trigger)
        Map<Id, Decimal> currentTotalsByVA = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT WhatId wid, SUM(Assigned_Percentage__c) sumPct
            FROM Task
            WHERE WhatId IN :vaIds
              AND Id NOT IN :contextTaskIds
            GROUP BY WhatId
        ]) {
            currentTotalsByVA.put((Id)ar.get('wid'), (Decimal)ar.get('sumPct'));
        }

        // incoming adds from this batch
        Map<Id, Decimal> proposedAddsByVA = new Map<Id, Decimal>();
        for (Task t : newList) {
            if (!isVA(t.WhatId, vaPrefix)) continue;
            Decimal add = nz(t.Assigned_Percentage__c);
            proposedAddsByVA.put(t.WhatId,
                nz(proposedAddsByVA.get(t.WhatId)) + add
            );
        }

        // vendor caps
        Map<Id, Vendor_Assignment__c> vaMap = new Map<Id, Vendor_Assignment__c>([
            SELECT Id, Name, Budget_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id IN :vaIds
        ]);

        // detect over-limit and compose friendly errors
        for (Task t : newList) {
            if (!isVA(t.WhatId, vaPrefix)) continue;

            Id vaId = t.WhatId;
            Decimal base   = nz(currentTotalsByVA.get(vaId));
            Decimal addAll = nz(proposedAddsByVA.get(vaId)); // batch contrib
            Decimal cap    = (vaMap.containsKey(vaId) && vaMap.get(vaId).Budget_Percentage__c != null)
                            ? vaMap.get(vaId).Budget_Percentage__c : 0;
            Decimal finalTotal = base + addAll;

            if (finalTotal > cap) {
                Decimal remain  = cap - base;  if (remain < 0) remain = 0;
                Decimal thisAdd = nz(t.Assigned_Percentage__c);

                t.addError(
                    'You can assign only ' + fmt(remain) + '% more for this Vendor Assignment '
                    + '(current ' + fmt(base) + '% of ' + fmt(cap) + '%). '
                    + 'You tried to add ' + fmt(thisAdd) + '%. '
                    + 'Reduce the Assigned Percentage.'
                );
            }
        }
    }

    // =====================================
    // 2) ROLLUP: UPDATE REMAINING % (AFTER)
    // =====================================
    // Called from after insert/update/undelete
    public static void recalcRemainingFromTasks(List<Task> newList, Map<Id, Task> oldMap) {
        Set<Id> vaIds = new Set<Id>();
        String p = vaKeyPrefix();

        if (newList != null) {
            for (Task t : newList) if (isVA(t.WhatId, p)) vaIds.add(t.WhatId);
        }
        if (oldMap != null) {
            for (Task o : oldMap.values()) if (isVA(o.WhatId, p)) vaIds.add(o.WhatId);
        }
        if (!vaIds.isEmpty()) recalcAndUpdate(vaIds);
    }

    // Called from after delete
    public static void recalcRemainingFromDeleted(List<Task> oldList) {
        Set<Id> vaIds = new Set<Id>();
        String p = vaKeyPrefix();
        if (oldList != null) {
            for (Task t : oldList) if (isVA(t.WhatId, p)) vaIds.add(t.WhatId);
        }
        if (!vaIds.isEmpty()) recalcAndUpdate(vaIds);
    }

    // Core rollup: recompute totals and update Vendor_Tasks_Remaining_Percentage__c
    private static void recalcAndUpdate(Set<Id> vaIds) {
        if (vaIds == null || vaIds.isEmpty()) return;

        // Caps
        Map<Id, Vendor_Assignment__c> vaMap = new Map<Id, Vendor_Assignment__c>([
            SELECT Id, Budget_Percentage__c, Vendor_Tasks_Remaining_Percentage__c
            FROM Vendor_Assignment__c
            WHERE Id IN :vaIds
        ]);

        // Current assigned total per VA
        Map<Id, Decimal> totalAssignedByVA = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT WhatId wid, SUM(Assigned_Percentage__c) totalPct
            FROM Task
            WHERE WhatId IN :vaIds
            GROUP BY WhatId
        ]) {
            totalAssignedByVA.put((Id)ar.get('wid'), (Decimal)ar.get('totalPct'));
        }

        // Prepare updates (only when value changes)
        List<Vendor_Assignment__c> updates = new List<Vendor_Assignment__c>();
        for (Id vaId : vaIds) {
            Vendor_Assignment__c va = vaMap.get(vaId);
            if (va == null) continue;

            Decimal cap      = nz(va.Budget_Percentage__c);
            Decimal assigned = nz(totalAssignedByVA.get(vaId));
            Decimal remaining = cap - assigned;
            if (remaining < 0) remaining = 0;

            if (va.Vendor_Tasks_Remaining_Percentage__c != remaining) {
                updates.add(new Vendor_Assignment__c(
                    Id = vaId,
                    Vendor_Tasks_Remaining_Percentage__c = remaining
                ));
            }
        }

        if (!updates.isEmpty()) {
            // Optional CRUD check to satisfy PMD rules
            if (!Schema.SObjectType.Vendor_Assignment__c.isUpdateable()) return;
            update updates;
        }
    }

    // =================
    // Small helpers
    // =================
    private static String vaKeyPrefix() {
        return Schema.getGlobalDescribe()
                     .get('Vendor_Assignment__c')
                     .getDescribe()
                     .getKeyPrefix();
    }
    private static Boolean isVA(Id whatId, String prefix) {
        return whatId != null && String.valueOf(whatId).startsWith(prefix);
    }
    private static Decimal nz(Decimal d) { return (d == null) ? 0 : d; }

    // Format percentages nicely for the error message
    private static String fmt(Decimal d) {
        if (d == null) return '0';
        String s = String.valueOf(d.setScale(2));
        if (s.endsWith('.00')) return s.substring(0, s.length()-3);
        if (s.endsWith('0'))   return s.substring(0, s.length()-1);
        return s;
    }
}