import { LightningElement, track, wire } from 'lwc';
import getProjectQuotationTypeValues
    from '@salesforce/apex/ProjectRequestController.getProjectQuotationTypeValues';

export default class ProjectRequestCodeComponent extends LightningElement {
    @track showScreen1 = true;
    @track showManualScreen = false;
    @track showAutomaticScreen = false;
 
    @track leadId;
    @track value = null; // ✅ store PICKLIST VALUE (ex: "Manual")
    @track label = null; // ✅ store PICKLIST LABEL (ex: "Custom Design")
    @track options = [];
 
    connectedCallback() {
        const urlParams = new URLSearchParams(window.location.search);
        this.leadId = urlParams.get('id');
    }
 
    get disableNext() {
        return !this.value;
    }
 
    @wire(getProjectQuotationTypeValues)
    wiredValues({ data, error }) {
        if (data) {
            this.options = data.map((item, index) => ({
                label: item.label,    // ✅ shown in UI
                value: item.value,    // ✅ stored/used for logic + save
                selected: this.value === item.value,
                cssClass: this.buildRowClass(item.value, index)
            }));
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error loading picklist values', error);
        }
    }
 
    buildRowClass(value, index) {
        const base = 'radio-row animate-stagger stagger-' + index;
        const selectedClass = this.value === value ? ' radio-row_selected' : '';
        return base + selectedClass;
    }
 
    handleChange(event) {
        const selectedValue = event.target.value; // ✅ picklist VALUE
        this.setSelectedValue(selectedValue);
    }
 
    handleRowClick(event) {
        const rowValue = event.currentTarget.dataset.value; // ✅ picklist VALUE
        if (rowValue) {
            this.setSelectedValue(rowValue);
        }
    }
 
    setSelectedValue(selectedValue) {
        this.value = selectedValue;
 
        // ✅ keep selected LABEL also (useful if you want to display it later)
        const match = this.options.find(o => o.value === selectedValue);
        this.label = match ? match.label : null;
 
        this.options = this.options.map((opt, index) => ({
            ...opt,
            selected: opt.value === this.value,
            cssClass: this.buildRowClass(opt.value, index)
        }));
    }
 
    goNext() {
        if (!this.value || !this.leadId) return;
 
        this.showScreen1 = false;
        this.showManualScreen = false;
        this.showAutomaticScreen = false;
 
        // ✅ Use PICKLIST VALUE checks (not label)
        if (this.value === 'Manual') {
            this.showManualScreen = true;
        } else if (this.value === 'Automation') {
            this.showAutomaticScreen = true;
        } else {
            // fallback
            this.showManualScreen = true;
        }
    }
 
    handlePrevious() {
        this.showScreen1 = true;
        this.showManualScreen = false;
        this.showAutomaticScreen = false;
    }
}