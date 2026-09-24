import { LightningElement,track } from 'lwc';

export default class MentorProject extends LightningElement {
    @track selectedVal = ''; 
    get options() {
        return [
            { label: 'Option 1', value: 'Archive' },
            { label: 'Option 2', value: 'Unarchive' },
        ];
    }

    handleRadioChange(event) {
        this.selectedVal = event.detail.value;
    }

    get isOptionOne(){
        return this.selectedVal=== 'Archive';
    }

    get isOptionTwo(){
        return this.selectedVal=== 'Unarchive';
    }
}