import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';

import SUPERVISOR_FIELD from '@salesforce/schema/Project__c.Supervisor_User__c';
// Confirmed Lookup API Name
import OPPORTUNITY_FIELD from '@salesforce/schema/Project__c.Project_Name__c'; 

import getFieldSetFields from '@salesforce/apex/VendorAssignmentController.getFieldSetFields';
import hasExistingRecords from '@salesforce/apex/VendorAssignmentController.hasExistingRecords';
import createVendorAssignments from '@salesforce/apex/VendorAssignmentController.createVendorAssignments';
import getExistingRecords from '@salesforce/apex/VendorAssignmentController.getExistingRecords';
import reparentFiles from '@salesforce/apex/VendorAssignmentController.reparentFiles';
import getAttachedFileNames from '@salesforce/apex/VendorAssignmentController.getAttachedFileNames';

export default class VendorAssignmentManager extends LightningElement {
    @api recordId; 
    @track isLoading = true;

    // View States
    showLanding = false;
    showCreation = false;
    showPreview = false;
    @track currentStep = 'start'; 
     @track showBackButton = false; 

    // Data Storage
    createFields = [];
    previewFieldSet = [];
    @track rows = [];
    @track previewData = [];

    // DATA LOADING FLAGS
    @track projectDataLoaded = false;
    @track fieldSetsLoaded = false;
    
    // Storage for fetched values
    @track fetchedSupervisor;
    @track fetchedOpportunity; 

    // Tracker to prevent infinite loops in renderedCallback
    initializedRows = new Set();

    get isReadyToRender() {
        return !this.isLoading && this.showCreation && this.fetchedOpportunity;
    }

    // 2. FETCH PROJECT DATA
    @wire(getRecord, { recordId: '$recordId', fields: [SUPERVISOR_FIELD, OPPORTUNITY_FIELD] })
    wiredProjectData({ error, data }) {
        if (data) {
            console.log('--- PROJECT DATA LOADED ---', data);
            this.fetchedSupervisor = getFieldValue(data, SUPERVISOR_FIELD);
            this.fetchedOpportunity = getFieldValue(data, OPPORTUNITY_FIELD);
            this.projectDataLoaded = true;
            this.checkLoadingState();
        } else if (error) {
            console.error('Error loading project data:', error);
            this.projectDataLoaded = true; 
            this.checkLoadingState();
        }
    }

    // 3. FORCE UPDATE FOR LOOKUP FILTER
    renderedCallback() {
        if (this.isReadyToRender && this.fetchedOpportunity) {
            
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => {
                const oppFields = this.template.querySelectorAll('[data-id="oppField"]');
                
                oppFields.forEach(field => {
                    const rowIndex = field.dataset.rowIndex;

                    // Only force-update if we haven't done it for this row yet
                    if (!this.initializedRows.has(rowIndex)) {
                        console.log('Forcing Update on Row:', rowIndex);
                        // Force assignment to trigger lookup filter refresh
                        field.value = this.fetchedOpportunity;
                        this.initializedRows.add(rowIndex);
                    }
                });
            }, 500); // 500ms delay to ensure DOM is ready
        }
    }

    connectedCallback() {
        this.init();
    }

    async init() {
        try {
            const cFields = await getFieldSetFields({ objectName: 'Vendor_Assignment__c', fieldSetName: 'Creation_Field_Set' });
            
            this.createFields = cFields.map(f => ({
                ...f,
                isProject: (f.fieldPath === 'Project__c'),
                isSupervisor: (f.fieldPath === 'Supervisor_User__c'),
                isOpp: (f.fieldPath === 'Opportunity__c'), 
                isStandard: !['Project__c', 'Supervisor_User__c', 'Opportunity__c'].includes(f.fieldPath)
            }));

            const pFields = await getFieldSetFields({ objectName: 'Vendor_Assignment__c', fieldSetName: 'Preview_Fieldset' });
            const createFieldNames = new Set(this.createFields.map(f => f.fieldPath));
            
            this.previewFieldSet = pFields.map(f => ({
                ...f,
                isEditable: createFieldNames.has(f.fieldPath)
            }));

            this.fieldSetsLoaded = true;
            this.checkLoadingState();

            const exists = await hasExistingRecords({ projectId: this.recordId });
            if (exists) {
                this.showLanding = true;
                this.currentStep = 'start';
                this.showBackButton = true;
            } else {
                this.showBackButton = false;
                this.initCreation();
            }

        } catch (error) {
            this.showToast('Error', 'Init failed: ' + (error.body ? error.body.message : error.message), 'error');
        }
    }

    checkLoadingState() {
        if (this.fieldSetsLoaded && this.projectDataLoaded) {
            this.isLoading = false;
        }
    }

    initCreation() {
        this.showCreation = true;
        this.currentStep = 'draft';
        this.addRow();
    }

    handleAddNewFromPreview() {
        this.rows = []; 
        this.addRow(); 
        this.showPreview = false;
        this.showCreation = true;
        this.showBackButton = true;
        this.currentStep = 'draft'; 
    }

    addRow() {
        this.rows.push({
            key: Date.now(),
            displayIndex: this.rows.length + 1,
            data: {}, 
            uploadedDocId: null,
            fileName: null
        });
    }

    deleteRow(event) {
        const index = event.currentTarget.dataset.index;
        if(this.rows.length > 1) {
            this.rows.splice(index, 1);
            this.rows = this.rows.map((r, i) => ({ ...r, displayIndex: i + 1 }));
            
            if (this.initializedRows.has(index)) {
                this.initializedRows.delete(index);
            }
        }
    }

    get isMultipleRows() { return this.rows.length > 1; }

    handleFieldChange(event) {
        const index = event.target.dataset.rowIndex;
        const fieldName = event.target.fieldName;
        this.rows[index].data[fieldName] = event.target.value;
    }

    handleUploadFinished(event) {
        const index = event.target.dataset.rowIndex;
        const files = event.detail.files;
        if(files.length > 0) {
            this.rows[index].uploadedDocId = files[0].documentId;
            this.rows[index].fileName = files[0].name;
            this.showToast('Success', 'Quotation uploaded', 'success');
        }
    }

    async handleCreate() {
        this.isLoading = true;
        try {
            const recordsToInsert = this.rows.map(r => ({
                ...r.data,
                Project__c: this.recordId,
                Supervisor_User__c: this.fetchedSupervisor, 
                Opportunity__c: this.fetchedOpportunity,    
                sobjectType: 'Vendor_Assignment__c'
            }));

            const savedRecords = await createVendorAssignments({ 
                records: recordsToInsert, 
                projectId: this.recordId 
            });

            const fileMap = {}; 
            this.rows.forEach((row, index) => {
                if(row.uploadedDocId && savedRecords[index]?.Id) {
                    fileMap[row.uploadedDocId] = savedRecords[index].Id;
                }
            });

            if(Object.keys(fileMap).length > 0) {
                await reparentFiles({ fileMap: fileMap });
            }

            this.showToast('Success', 'Vendor Assignments created.', 'success');
            this.showCreation = false;
            this.showBackButton = true;
            this.goToPreview(); 

        } catch (error) {
            let msg = 'Unknown Error';
            if (error.body?.message) msg = error.body.message;
            else if (error.body?.pageErrors?.length > 0) msg = error.body.pageErrors[0].message;
            this.showToast('Error', 'Creation failed: ' + msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async goToPreview() {
        this.isLoading = true;
        this.showLanding = false;
        this.showCreation = false; 
        this.showPreview = true;
        this.currentStep = 'review';
        
        try {
            const fieldsToQuery = this.previewFieldSet.map(f => f.fieldPath);
            const data = await getExistingRecords({ 
                projectId: this.recordId, 
                queryFields: fieldsToQuery 
            });

            const recordIds = data.map(r => r.Id);
            const fileMap = await getAttachedFileNames({ parentIds: recordIds });

            this.previewData = data.map((record, index) => {
                const fileName = fileMap[record.Id]; 
                return {
                    ...record,
                    serialNumber: index + 1,
                    existingFileName: fileName || null, 
                    uploadLabel: fileName ? 'Replace File' : 'Upload Quotation'
                };
            });

        } catch (error) {
            this.showToast('Error', 'Could not load preview: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handlePreviewUpload(event) {
        const files = event.detail.files;
        const recordId = event.target.dataset.id;
        if(files.length > 0) {
            const newFileName = files[0].name;
            this.previewData = this.previewData.map(rec => {
                if(rec.Id === recordId) {
                    return { ...rec, existingFileName: newFileName, uploadLabel: 'Replace File' };
                }
                return rec;
            });
            this.showToast('Success', 'File updated successfully', 'success');
        }
    }

    async handleFinalSave() {
        this.isLoading = true;
        const forms = this.template.querySelectorAll('lightning-record-edit-form');
        const submitPromises = [];
        forms.forEach(form => {
            const p = new Promise((resolve, reject) => {
                let handleSuccess, handleError;
                const cleanup = () => {
                    form.removeEventListener('success', handleSuccess);
                    form.removeEventListener('error', handleError);
                };
                handleSuccess = () => { cleanup(); resolve('success'); };
                handleError = (errorPayload) => { cleanup(); reject(errorPayload); };
                form.addEventListener('success', handleSuccess);
                form.addEventListener('error', handleError);
                form.submit();
            });
            submitPromises.push(p);
        });

        try {
            await Promise.all(submitPromises);
            this.showToast('Success', 'All records saved successfully!', 'success');
            this.closeAction();
        } catch (error) {
            this.showToast('Error', 'Some records failed to save: ' + (error.body ? error.body.message : error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    closeAction() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}