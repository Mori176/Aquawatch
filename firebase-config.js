import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-app.js";

import { getDatabase } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js";

import { getAuth } from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";

const firebaseConfig = {
  apiKey: "AIzaSyAH44Hg0JYlTpv9AbV-0n_ynYy5Q8nXNE0",
  authDomain: "myfishapp-4e3e6.firebaseapp.com",
  databaseURL: "https://myfishapp-4e3e6-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "myfishapp-4e3e6",
  storageBucket: "myfishapp-4e3e6.firebasestorage.app",
  messagingSenderId: "909011184334",
  appId: "1:909011184334:web:7ebb3571635b93e1a37e9f",
  measurementId: "G-JQL6VNHQS5"
};

const app = initializeApp(firebaseConfig);

const db = getDatabase(app);

const auth = getAuth(app);

window.db = db;
window.auth = auth;