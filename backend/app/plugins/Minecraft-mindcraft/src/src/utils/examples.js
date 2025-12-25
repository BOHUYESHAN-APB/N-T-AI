import { cosineSimilarity } from './math.js';
import { stringifyTurns, wordOverlapScore } from './text.js';

export class Examples {
    constructor(model, select_num=2) {
        this.examples = [];
        this.model = model;
        this.select_num = select_num;
        this.embeddings = {};
    }

    turnsToText(turns) {
        let messages = '';
        for (let turn of turns) {
            if (turn.role !== 'assistant')
                messages += turn.content.substring(turn.content.indexOf(':')+1).trim() + '\n';
        }
        return messages.trim();
    }

    async load(examples) {
        this.examples = examples;
        if (!this.model) return; // Early return if no embedding model
        
        if (this.select_num === 0)
            return;

        try {
            // Use batched Promise.all to load embeddings to avoid overwhelming the backend
            // but still maintain speed.
            const batchSize = 10;
            for (let i = 0; i < examples.length; i += batchSize) {
                const batch = examples.slice(i, i + batchSize);
                const tasks = batch.map(async (example) => {
                    const turn_text = this.turnsToText(example);
                    if (this.embeddings[turn_text]) return;
                    
                    const embedding = await this.model.embed(turn_text);
                    this.embeddings[turn_text] = embedding;
                    console.log(`Embedding complete for batch item: ${turn_text.substring(0, 30)}...`);
                });
                await Promise.all(tasks);
                console.log(`Completed embedding batch ${Math.floor(i/batchSize) + 1}/${Math.ceil(examples.length/batchSize)}`);
            }
        } catch (err) {
            console.warn('Error with embedding model, using word-overlap instead.');
            this.model = null;
        }
    }

    async getRelevant(turns) {
        if (this.select_num === 0)
            return [];

        let turn_text = this.turnsToText(turns);
        if (this.model !== null) {
            let embedding = await this.model.embed(turn_text);
            this.examples.sort((a, b) => 
                cosineSimilarity(embedding, this.embeddings[this.turnsToText(b)]) -
                cosineSimilarity(embedding, this.embeddings[this.turnsToText(a)])
            );
        }
        else {
            this.examples.sort((a, b) => 
                wordOverlapScore(turn_text, this.turnsToText(b)) -
                wordOverlapScore(turn_text, this.turnsToText(a))
            );
        }
        let selected = this.examples.slice(0, this.select_num);
        return JSON.parse(JSON.stringify(selected)); // deep copy
    }

    async createExampleMessage(turns) {
        let selected_examples = await this.getRelevant(turns);

        console.log('selected examples:');
        for (let example of selected_examples) {
            console.log('Example:', example[0].content)
        }

        let msg = 'Examples of how to respond:\n';
        for (let i=0; i<selected_examples.length; i++) {
            let example = selected_examples[i];
            msg += `Example ${i+1}:\n${stringifyTurns(example)}\n\n`;
        }
        return msg;
    }
}