// 🔑 Replace with your Firebase config
const firebaseConfig = {
  apiKey: "AIzaSyDQJlmjJsq86TwNvR-zO7GWKpCPwOYCvrI",
  authDomain: "roadresq-e4b7b.firebaseapp.com",
  projectId: "roadresq-e4b7b",
  storageBucket: "roadresq-e4b7b.firebasestorage.app",
  messagingSenderId: "47837867447",
  appId: "1:47837867447:web:2cc1577aabacb9cf2bcc32",
  measurementId: "G-22B1DBM203"
};


// 1. Initialize Firebase
firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();

// 2. Sign up a new user
function signUp() {
  const email = document.getElementById("email").value;
  const password = document.getElementById("password").value;

  auth.createUserWithEmailAndPassword(email, password)
    .then(() => {
      document.getElementById("message").innerText = "✅ Account Created!";
    })
    .catch((error) => {
      document.getElementById("message").innerText = "❌ " + error.message;
    });
}

// 3. Log in an existing user
function logIn() {
  const email = document.getElementById("email").value;
  const password = document.getElementById("password").value;

  auth.signInWithEmailAndPassword(email, password)
    .then(() => {
      document.getElementById("message").innerText = "✅ Logged In!";
    })
    .catch((error) => {
      document.getElementById("message").innerText = "❌ " + error.message;
    });
}

// 4. Log out a user
function logOut() {
  auth.signOut()
    .then(() => {
      document.getElementById("message").innerText = "✅ Logged Out!";
    });
}
