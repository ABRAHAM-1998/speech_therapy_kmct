import os
import numpy as np
import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder

# Configuration
DATA_DIR = 'assets/VOICED_DATASET'
MODEL_DIR = 'assets/models'
SAMPLE_LENGTH = 16000 # 1 second @ 16kHz (Standard)

def load_data():
    X = []
    y = []
    
    files = [f for f in os.listdir(DATA_DIR) if f.endswith('.txt') and not f.endswith('-info.txt')]
    print(f"Found {len(files)} data files.")

    for filename in files:
        # Load raw audio samples
        file_path = os.path.join(DATA_DIR, filename)
        try:
            # Assuming single column of float values
            data = pd.read_csv(file_path, header=None).values.flatten()
            
            # Normalize and pad/truncate
            if len(data) > SAMPLE_LENGTH:
                data = data[:SAMPLE_LENGTH]
            else:
                data = np.pad(data, (0, SAMPLE_LENGTH - len(data)), 'constant')
            
            X.append(data)
            
            # Load label
            info_filename = filename.replace('.txt', '-info.txt')
            info_path = os.path.join(DATA_DIR, info_filename)
            with open(info_path, 'r') as f:
                label = f.read().strip()
                # Simplify labels for demo if needed, or keep full
                y.append(label)
                
        except Exception as e:
            print(f"Skipping {filename}: {e}")

    return np.array(X), np.array(y)

def train_and_save():
    print("Loading data...")
    X, y = load_data()
    
    if len(X) == 0:
        print("No data found! Check assets/VOICED_DATASET path.")
        return

    # Encode labels
    le = LabelEncoder()
    y_enc = le.fit_transform(y)
    classes = le.classes_
    print(f"Classes: {classes}")
    
    # Save Labels
    with open(os.path.join(MODEL_DIR, 'labels.txt'), 'w') as f:
        f.write('\n'.join(classes))

    # Reshape for Conv1D: (Samples, TimeSteps, Features) -> (N, 16000, 1)
    X = X.reshape(X.shape[0], X.shape[1], 1)
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(X, y_enc, test_size=0.2, random_state=42)

    # Build Simple Model (Audio Compatible)
    model = tf.keras.models.Sequential([
        tf.keras.layers.Input(shape=(SAMPLE_LENGTH, 1)),
        tf.keras.layers.Conv1D(16, 3, activation='relu', padding='same'),
        tf.keras.layers.MaxPooling1D(2),
        tf.keras.layers.Conv1D(32, 3, activation='relu', padding='same'),
        tf.keras.layers.GlobalAveragePooling1D(),
        tf.keras.layers.Dense(32, activation='relu'),
        tf.keras.layers.Dense(len(classes), activation='softmax')
    ])

    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    
    print("Training model...")
    model.fit(X_train, y_train, epochs=5, validation_data=(X_test, y_test))

    # Convert to TFLite
    print("Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS, # Enable TensorFlow Lite ops.
        tf.lite.OpsSet.SELECT_TF_OPS # Enable TensorFlow ops.
    ]
    tflite_model = converter.convert()

    # Save
    save_path = os.path.join(MODEL_DIR, 'speech_classifier.tflite')
    with open(save_path, 'wb') as f:
        f.write(tflite_model)
    
    print(f"Model saved to {save_path}")

if __name__ == '__main__':
    train_and_save()
