import { LightningElement, api, track, wire } from 'lwc';
import saveExpenseSheet from '@salesforce/apex/ExpenseSheetController.saveExpenseSheet';
import getProjectExpenses from '@salesforce/apex/ExpenseSheetController.getProjectExpenses';
import getDraftDetails from '@salesforce/apex/ExpenseSheetController.getDraftDetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import LightningConfirm from 'lightning/confirm';

export default class ExpenseSheetEntry extends NavigationMixin(LightningElement) {
    @api recordId; 
    @track activeTab = 'new';
    @track currentSheetId = null; 

    // --- HISTORY TABLE ---
    @track expenseHistory = [];
    @track historyColumns = [
        // Allow text to wrap if it gets too tight
        { label: 'Sheet No', fieldName: 'Name', type: 'button', wrapText: true, 
          typeAttributes: { label: { fieldName: 'Name' }, variant: 'base' } },
        { label: 'Date', fieldName: 'Sheet_Date__c', type: 'date', initialWidth: 100 },
        { label: 'Total', fieldName: 'Grand_Total__c', type: 'currency', initialWidth: 100,
          typeAttributes: { currencyCode: 'INR' } },
        { label: 'Status', fieldName: 'Status__c', initialWidth: 90 },
        // Let 'Created By' take whatever space is left
        { label: 'Created By', fieldName: 'CreatedBy_Name', wrapText: true },
        // Pin the action column to the right
        { type: 'button-icon', initialWidth: 50, typeAttributes: { 
            iconName: 'utility:edit', name: 'edit_draft', title: 'Edit Draft', variant: 'bare',
            disabled: { fieldName: 'isLocked' } 
        }}
    ];

    // --- FORM DATA ---
    @track materialRows = [{ id: 1, name: '', description: '', brand: '', qty: 0, rate: 0, amount: 0 }];
    @track otherRows = [{ id: 1, description: '', amount: 0 }];
    @track grandTotal = 0;
    
    // --- FILE DATA ---
    @track uploadedFiles = []; 
    @track existingFiles = []; 
    
    isSaving = false;

    // --- TAB HANDLING ---
    handleTabActive(event) {
        this.activeTab = event.target.value;
    }

    // --- FETCH HISTORY ---
    @wire(getProjectExpenses, { projectId: '$recordId' })
    wiredExpenses({ error, data }) {
        if (data) {
            this.expenseHistory = data.map(row => ({
                ...row,
                CreatedBy_Name: row.CreatedBy ? row.CreatedBy.Name : '', 
                isLocked: row.Status__c !== 'Draft' 
            }));
        } else if (error) {
            console.error('Error fetching history:', error);
            this.expenseHistory = [];
        }
    }

    // --- ROW ACTIONS ---
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'edit_draft') {
            this.loadDraftForEditing(row.Id);
        } else {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: { recordId: row.Id, actionName: 'view' }
            });
        }
    }

    // --- LOAD DRAFT ---
    loadDraftForEditing(sheetId) {
        this.isSaving = true;
        getDraftDetails({ sheetId: sheetId })
            .then(data => {
                this.currentSheetId = data.sheetId; 
                this.grandTotal = data.grandTotal;
                this.materialRows = [];
                this.otherRows = [];
                this.uploadedFiles = []; 
                this.existingFiles = data.existingFiles || []; 

                if (data.items) {
                    data.items.forEach(item => {
                        const rowData = {
                            id: Date.now() + Math.random(), 
                            name: item.name, brand: item.brand, qty: item.qty, rate: item.rate, amount: item.amount, description: item.description
                        };
                        if (item.type === 'Material') {
                            this.materialRows.push(rowData);
                        } else {
                            this.otherRows.push({ id: rowData.id, description: item.description, amount: item.amount });
                        }
                    });
                }
                
                if (this.materialRows.length === 0) { this.addMaterialRow(); }
                if (this.otherRows.length === 0) { this.addOtherRow(); }

                this.calculateGrandTotal();
                this.activeTab = 'new'; 
                this.showToast('Draft Loaded', 'You can now edit and submit.', 'info');
            })
            .catch(error => {
                console.error('Error loading draft:', error);
                this.showToast('Error', 'Could not load draft: ' + (error.body ? error.body.message : error.message), 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    // --- ROW HELPERS ---
    addMaterialRow() { this.materialRows.push({ id: Date.now(), name: '', description: '', brand: '', qty: 0, rate: 0, amount: 0 }); }
    
    removeMaterialRow(event) {
        const index = event.currentTarget.dataset.index;
        if (this.materialRows.length > 1) { 
            this.materialRows.splice(index, 1); 
            this.calculateGrandTotal(); 
        }
    }

    handleMaterialChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.name;
        this.materialRows[index][field] = event.target.value;
        if (field === 'qty' || field === 'rate') {
            this.materialRows[index].amount = (this.materialRows[index].qty || 0) * (this.materialRows[index].rate || 0);
        }
        this.calculateGrandTotal();
    }

    addOtherRow() { this.otherRows.push({ id: Date.now(), description: '', amount: 0 }); }

    removeOtherRow(event) {
        const index = event.currentTarget.dataset.index;
        if (this.otherRows.length > 1) { 
            this.otherRows.splice(index, 1); 
            this.calculateGrandTotal(); 
        }
    }

    handleOtherChange(event) {
        const index = event.target.dataset.index;
        const field = event.target.name;
        this.otherRows[index][field] = event.target.value;
        this.calculateGrandTotal();
    }

    calculateGrandTotal() {
        let mTotal = this.materialRows.reduce((sum, row) => sum + Number(row.amount), 0);
        let oTotal = this.otherRows.reduce((sum, row) => sum + Number(row.amount), 0);
        this.grandTotal = mTotal + oTotal;
    }

    handleFileChange(event) {
        const files = event.target.files;
        if (files) {
            for(let i=0; i<files.length; i++) {
                const file = files[i];
                const reader = new FileReader();
                reader.onload = () => {
                    this.uploadedFiles.push({ name: file.name, base64: reader.result.split(',')[1] });
                };
                reader.readAsDataURL(file);
            }
        }
    }

    async handleSaveDraft() {
        if (this.grandTotal <= 0) return;
        const result = await LightningConfirm.open({
            message: 'Save changes as Draft? No email will be sent.',
            variant: 'headerless',
            label: 'Confirm Save Draft'
        });
        if (result) { this.processSave('Draft'); }
    }

    async handleSubmit() {
        if (this.grandTotal <= 0) return;
        const result = await LightningConfirm.open({
            message: 'Submit for Approval? This will generate the PDF and email the Manager.',
            variant: 'headerless',
            label: 'Confirm Submission',
            theme: 'warning'
        });
        if (result) { this.processSave('Submitted'); }
    }

    processSave(status) {
        this.isSaving = true;
        const allItems = [];
        this.materialRows.forEach(row => { if(row.name) allItems.push({ type: 'Material', ...row }); });
        this.otherRows.forEach(row => { if(row.description) allItems.push({ type: 'Other', name: '', brand: '', qty: 0, rate: 0, ...row }); });

        const payload = {
            sheetId: this.currentSheetId,
            projectId: this.recordId,
            grandTotal: this.grandTotal,
            status: status,
            items: allItems,
            billFiles: this.uploadedFiles 
        };

        saveExpenseSheet({ jsonData: JSON.stringify(payload) })
            .then(() => {
                const msg = status === 'Submitted' ? 'Submitted Successfully!' : 'Draft Saved.';
                this.showToast('Success', msg, 'success');
                if (status === 'Submitted') {
                     this.currentSheetId = null;
                     this.materialRows = [{ id: 1, name: '', description: '', brand: '', qty: 0, rate: 0, amount: 0 }];
                     this.otherRows = [{ id: 1, description: '', amount: 0 }];
                     this.grandTotal = 0;
                     this.uploadedFiles = [];
                     this.existingFiles = [];
                }
                this.dispatchEvent(new CloseActionScreenEvent());
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}