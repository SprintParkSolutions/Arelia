import { LightningElement, api, track } from "lwc";
import getPaymentTerms from "@salesforce/apex/PaymentTermController.getPaymentTerms";
import savePaymentTerms from "@salesforce/apex/PaymentTermController.savePaymentTerms";
import submitToManager from "@salesforce/apex/PaymentTermController.submitToManager";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

export default class PaymentTermManagerAction extends LightningElement {
    _recordId;
    @api set recordId(value) {
        this._recordId = value;
        if (this._recordId) { this.fetchData(); }
    }
    get recordId() { return this._recordId; }

    @track terms = [];
    @track deletedTermIds = [];
    @track currentTotal = 0;
    @track isLoading = true; 
    @track isEditMode = false;      
    @track showResumeBtn = false;   
    @track rawStatus = 'Not Sent'; 
    @track managerRemarks = '';
    @track clientRemarks = '';
    
    @track isProjectContext = false; 

    fetchData() {
        this.isLoading = true;
        getPaymentTerms({ recordId: this.recordId })
            .then(data => {
                if (data && data.opportunity) {
                    this.isProjectContext = (data.objectType === 'Project__c');

                    // Handle missing fields for Project context safely
                    this.rawStatus = data.opportunity.Payment_Terms_Status__c || 'Not Sent';
                    this.managerRemarks = data.opportunity.Payment_Term_Manager_Remarks__c || '';
                    this.clientRemarks = data.opportunity.Payment_Term_Client_Remarks__c || '';

                    const termList = data.terms || [];
                    if (termList.length === 0) {
                        this.terms = [{TempId: Date.now(), serialNumber: 1, Term_Label__c: "", Percentage__c: 0, Due_Date__c: null, Payment_Received__c: false}];
                        this.isEditMode = !this.isProjectContext; 
                        this.showResumeBtn = false;
                    } else {
                        this.terms = termList.map((item, index) => ({
                            ...item, TempId: item.Id, serialNumber: index + 1, Term_Label__c: item.Term_Label__c || item.Name || ""
                        }));
                        if (!this.isEditMode) { this.showResumeBtn = true; }
                    }
                    this.calculateTotal();
                }
            })
            .catch(error => {
                console.error('Fetch error:', error);
                this.showToast("Error", "Failed to refresh data.", "error");
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    calculateTotal() { 
        this.currentTotal = this.terms.reduce((s,i) => s + (parseFloat(i.Percentage__c) || 0), 0); 
    }
    
    get isInvalid() { return Math.abs(this.currentTotal - 100) > 0.01; }
    
    get totalStatusClass() { return this.isInvalid ? "slds-text-color_error" : "slds-text-color_success"; }
    
    // --- Action Handlers ---

    async handleSubmitToManager() {
        if(this.isInvalid) { 
            await LightningAlert.open({ message: 'Total must equal 100%.', theme: 'error', label: 'Validation Error' });
            return; 
        }
        const result = await LightningConfirm.open({ message: 'Submit for Manager Approval?', variant: 'header', label: 'Confirm Action', theme: 'brand' });
        if (result) {
            this.isLoading = true;
            submitToManager({ recordId: this.recordId })
                .then(() => {
                    this.showToast("Success", "Sent for Manager Approval", "success");
                    this.dispatchEvent(new CloseActionScreenEvent());
                    this.fetchData(); 
                })
                .catch(error => {
                    console.error('Submission error:', error);
                    this.showToast("Error", error.body?.message || "Submission failed", "error");
                })
                .finally(() => { this.isLoading = false; });
        }
    }

    async executeSave(shouldSubmit) {
        if (this.isInvalid) return;
        this.isLoading = true;
        const termsToSave = this.terms.map(row => { 
            let c = {...row}; 
            delete c.TempId; 
            delete c.serialNumber; 
            return c; 
        });

        try {
            await savePaymentTerms({ terms: termsToSave, recordId: this.recordId, termsToDelete: this.deletedTermIds });
            this.showToast("Success", "Status Updated.", "success");
            this.dispatchEvent(new CloseActionScreenEvent());
            
            if (!this.isProjectContext) {
                this.isEditMode = false;
                this.showResumeBtn = false; 
            }

            if (shouldSubmit && !this.isProjectContext) {
                await submitToManager({ recordId: this.recordId });
                this.showToast("Success", "Submitted for Approval.", "success");
                this.dispatchEvent(new CloseActionScreenEvent());
            }
            this.fetchData(); 
        } catch (error) {
            console.error('Save error:', error);
            this.showToast("Error", error.body?.message || "Operation failed", "error");
            this.isLoading = false;
        }
    }

    handleProjectUpdate() {
        this.executeSave(false);
    }

    handleSave() { this.executeSave(false); }
    handleSaveAndSubmit() { this.executeSave(true); }
    handleEditMode() { this.isEditMode = true; }
    handleResume() { this.showResumeBtn = false; }
    handleCancel() { this.fetchData(); this.isEditMode = false; this.showResumeBtn = false; }
    
    handleAddRow() { 
        this.terms.push({TempId: Date.now(), serialNumber: this.terms.length+1, Term_Label__c:"", Percentage__c:0, Due_Date__c: null, Payment_Received__c: false}); 
        this.calculateTotal(); 
    }

    handleDeleteRow(event) { 
        const idx = event.currentTarget.dataset.index;
        if(this.terms[idx].Id) this.deletedTermIds.push(this.terms[idx].Id); 
        this.terms.splice(idx,1); 
        this.terms = this.terms.map((t, i) => ({ ...t, serialNumber: i + 1 }));
        this.calculateTotal(); 
    }

    handleChange(event) { 
        const idx = event.currentTarget.dataset.index; 
        const f = event.currentTarget.dataset.field; 
        this.terms[idx][f] = event.target.type === "checkbox" ? event.target.checked : event.target.value;
        if(f==="Percentage__c") this.calculateTotal(); 
    }

    showToast(title, message, variant) { 
        this.dispatchEvent(new ShowToastEvent({ title, message, variant })); 
    }
}