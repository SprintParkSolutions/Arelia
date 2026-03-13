import { LightningElement, api, track, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import { getRecordNotifyChange } from "lightning/uiRecordApi";

import getBudgetReview from "@salesforce/apex/OpportunityBudgetReviewController.getBudgetReview";
import saveChildRows from "@salesforce/apex/OpportunityBudgetReviewController.saveChildRows";
import submitToClient from "@salesforce/apex/OpportunityBudgetReviewController.submitToClient";

export default class OpportunityBudgetReview extends LightningElement {
    @api recordId;
    loading = true;
    isReadOnly = true;
    errorText = "";

    // Track numbers for calculation
    @track customerBudget = null;
    @track supervisorBudget = null;
    @track finalBudget = null;
    
    // Track strings for inputs
    @track customerBudgetText = "";
    @track supervisorBudgetText = "";
    @track duration = "";

    @track architectureRows = [];
    @track paymentTermRows = [];
    architectureDraftValues = [];
    paymentTermDraftValues = [];

    wiredResult;

    @wire(getBudgetReview, { opportunityId: "$recordId" })
    wiredBudget(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.loading = false;
        if (error) { this.errorText = this.err(error); return; }
        if (data) { this.applyDto(data); }
    }

    get editButtonLabel() { return this.isReadOnly ? "Edit" : "Cancel"; }
    get isSaveDisabled() { return this.loading || this.isReadOnly || !!this.errorText; }
    get durationLabel() { return this.duration ? this.duration : "—"; }

    get architectureColumns() {
        return [
            { label: "Design", fieldName: "name", type: "text" },
            { label: "Budget (₹)", fieldName: "amount", type: "number", editable: !this.isReadOnly }
        ];
    }

    get paymentTermColumns() {
        return [
            { label: "Term", fieldName: "termLabel", type: "text", editable: !this.isReadOnly },
            { label: "%", fieldName: "displayPercent", type: "percent", editable: !this.isReadOnly },
            { label: "Due Date", fieldName: "dueDate", type: "date", editable: !this.isReadOnly }
        ];
    }

    toggleEdit() {
        this.isReadOnly = !this.isReadOnly;
        if (this.isReadOnly) refreshApex(this.wiredResult);
    }

    // --- FIXED INPUT HANDLERS ---
    // Using event.detail.value is more reliable for lightning-input
    onCustomerInput(e) {
        const val = e.detail.value; 
        this.customerBudgetText = val;
        this.customerBudget = this.toNumber(val);
    }

    onSupervisorInput(e) {
        const val = e.detail.value;
        this.supervisorBudgetText = val;
        this.supervisorBudget = this.toNumber(val);
        this.finalBudget = this.supervisorBudget; 
    }

    onDurationInput(e) { 
        this.duration = e.detail.value; 
    }

    onArchChange(e) { this.architectureDraftValues = e.detail.draftValues; }
    onTermChange(e) { this.paymentTermDraftValues = e.detail.draftValues; }

    async save() {
        this.loading = true;
        
        // Debug Log to verify data right before sending
        console.log('SAVING DATA:', {
            cust: this.customerBudget,
            sup: this.supervisorBudget,
            dur: this.duration
        });

        try {
            const mergedArch = this.mergeDrafts(this.architectureRows, this.architectureDraftValues);
            const mergedTerms = this.mergeDrafts(this.paymentTermRows, this.paymentTermDraftValues);

            const termsPayload = mergedTerms.map((p) => ({
                id: p.id,
                termLabel: p.termLabel,
                percentage: (p.displayPercent !== undefined && p.displayPercent !== null) ? this.toNumber(p.displayPercent) * 100 : null,
                dueDate: p.dueDate,
                paymentReceived: p.paymentReceived
            }));

            const dto = await saveChildRows({
                opportunityId: this.recordId,
                req: {
                    inputCustomerBudget: this.customerBudget,
                    inputSupervisorBudget: this.supervisorBudget,
                    inputDuration: this.duration,
                    architectureRows: mergedArch.map((r) => ({ id: r.id, amount: this.toNumber(r.amount) })),
                    paymentTerms: termsPayload
                }
            });

            // Force UI refresh
            await getRecordNotifyChange([{ recordId: this.recordId }]);
            
            this.applyDto(dto);
            await refreshApex(this.wiredResult);
            
            this.toast("Success", "Budget updated successfully.", "success");
            this.isReadOnly = true;
            this.architectureDraftValues = [];
            this.paymentTermDraftValues = [];
            return true;

        } catch (e) {
            console.error('Save Error:', e);
            this.toast("Error", this.err(e), "error");
            return false;
        } finally {
            this.loading = false;
        }
    }

    async handleSendToClient() {
        const saved = await this.save(); 
        if (!saved) return;

        this.loading = true;
        try {
            await submitToClient({ recordId: this.recordId });
            this.toast("Success", "Budget sent for Client Approval.", "success");
        } catch (error) {
            this.toast("Error Sending Email", this.err(error), "error");
        } finally {
            this.loading = false;
        }
    }

    applyDto(dto) {
        if (!dto) return;

        this.customerBudget = dto.customerBudget ?? null;
        this.supervisorBudget = dto.supervisorBudget ?? null;
        this.finalBudget = dto.finalBudget ?? null;
        
        // Convert numbers to strings for the input fields to display correctly
        this.customerBudgetText = this.customerBudget ? String(this.customerBudget) : "";
        this.supervisorBudgetText = this.supervisorBudget ? String(this.supervisorBudget) : "";
        
        this.duration = dto.estimatedDuration ?? "";
        
        this.architectureRows = (dto.architectureRows || []).map((r) => ({ ...r }));
        this.paymentTermRows = (dto.paymentTerms || []).map((p) => ({
            ...p,
            displayPercent: p.percentage ? Number(p.percentage) / 100 : null
        }));
    }

    toNumber(value) {
        if (value == null || value === '') return null;
        const s = String(value).replace(/,/g, "").replace(/[^\d.-]/g, "").trim();
        return s ? parseFloat(s) : null;
    }

    mergeDrafts(base, drafts) {
        const map = new Map((base || []).map((r) => [r.id, { ...r }]));
        (drafts || []).forEach((d) => { if(map.has(d.id)) map.set(d.id, { ...map.get(d.id), ...d }); });
        return Array.from(map.values());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    err(error) {
        return error?.body?.message || error?.message || "Unknown error";
    }
}